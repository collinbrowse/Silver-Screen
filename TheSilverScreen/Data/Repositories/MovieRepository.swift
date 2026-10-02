//
//  MovieRepository.swift
//  TheSilverScreen
//

import Foundation

struct MoviePage: Sendable, Equatable {
    let movies: [Movie]
    let page: Int
    let hasMore: Bool
}

final class MovieRepository: Sendable {
    private let client: any HTTPClient
    private let requests: TMDBRequestBuilder
    private let logger: any AppLogging
    private let sleeper: any Sleeper

    init(
        client: any HTTPClient,
        apiKey: String,
        logger: any AppLogging,
        sleeper: any Sleeper = TaskSleeper()
    ) {
        self.client = client
        self.requests = TMDBRequestBuilder(apiKey: apiKey)
        self.logger = logger
        self.sleeper = sleeper
    }

    func topMovies(page: Int) async throws -> MoviePage {
        try await fetchMoviePage(
            path: "discover/movie",
            context: "Top movies",
            queryItems: listQuery(
                page: page,
                extra: [
                    URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                    URLQueryItem(name: "vote_count.gte", value: "200"),
                    URLQueryItem(name: "without_genres", value: "99,10755"),
                ]
            )
        )
    }

    /// One Discover page for the All window. Now Playing and Upcoming use their own lists.
    func discover(
        sort: BrowseSort,
        window: BrowseWindow,
        page: Int,
        locale: Locale = .current,
        today: Date = Date(),
        timeZone: TimeZone = .current,
        genreIDs: [Int] = []
    ) async throws -> MoviePage {
        try await fetchMoviePage(
            path: DiscoverKind.movie.path,
            context: "Browse movies",
            queryItems: DiscoverQuery.items(
                kind: .movie,
                sort: sort,
                window: window,
                page: page,
                locale: locale,
                today: today,
                timeZone: timeZone,
                genreIDs: genreIDs
            )
        )
    }

    /// Movies currently in theaters (`/movie/now_playing`). The list is not sortable.
    func nowPlaying(page: Int, locale: Locale = .current) async throws -> MoviePage {
        try await fetchMoviePage(
            path: "movie/now_playing",
            context: "Now playing",
            queryItems: TMDBLocale.queryItems(locale: locale, page: page)
        )
    }

    /// Movies with a future theatrical date (`/movie/upcoming`). The list is not sortable.
    func upcoming(page: Int, locale: Locale = .current) async throws -> MoviePage {
        try await fetchMoviePage(
            path: "movie/upcoming",
            context: "Upcoming",
            queryItems: TMDBLocale.queryItems(locale: locale, page: page)
        )
    }

    /// Popular movies, used as the Search tab's landing list.
    func popular(page: Int, locale: Locale = .current) async throws -> MoviePage {
        try await fetchMoviePage(
            path: "movie/popular",
            context: "Popular movies",
            queryItems: TMDBLocale.queryItems(locale: locale, page: page)
        )
    }

    /// Type-ahead movie search. `query` is sent as a query item, never logged.
    func searchMovies(query: String, page: Int, locale: Locale = .current) async throws -> MoviePage {
        try await fetchMoviePage(
            path: "search/movie",
            context: "Movie search",
            queryItems: TMDBLocale.queryItems(
                locale: locale,
                page: page,
                extra: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "include_adult", value: "false"),
                ]
            )
        )
    }

    /// Movies in any of these genres, most popular first.
    func movies(inGenres ids: [Int], page: Int, locale: Locale = .current) async throws -> MoviePage {
        try await fetchMoviePage(
            path: "discover/movie",
            context: "Movies by genre",
            queryItems: genreQueryItems(ids: ids, page: page, locale: locale)
        )
    }

    private func genreQueryItems(ids: [Int], page: Int, locale: Locale) -> [URLQueryItem] {
        TMDBLocale.queryItems(
            locale: locale,
            page: page,
            extra: [
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "with_genres", value: ids.map(String.init).joined(separator: "|")),
            ]
        )
    }

    private func listQuery(page: Int, locale: Locale = .current, extra: [URLQueryItem] = []) -> [URLQueryItem] {
        TMDBLocale.queryItems(locale: locale, page: page, extra: extra)
    }

    private func fetchMoviePage(
        path: String,
        context: String,
        queryItems: [URLQueryItem]
    ) async throws -> MoviePage {
        let request = try requests.get(path: path, queryItems: queryItems)
        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: context,
            sleeper: sleeper
        )

        do {
            let movies = try Self.decodeMovies(from: data, logger: logger)
            let pageMeta = try JSONDecoder().decode(MovieListPageMeta.self, from: data)
            return MoviePage(
                movies: movies,
                page: pageMeta.page,
                hasMore: pageMeta.page < pageMeta.totalPages
            )
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("\(context) page metadata decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    func movieDetail(id: Int, locale: Locale = .current) async throws -> MovieDetail {
        let request = try requests.get(
            path: "movie/\(id)",
            queryItems: [
                URLQueryItem(name: "language", value: TMDBLocale.languageTag(for: locale)),
                URLQueryItem(name: "append_to_response", value: "credits,images,similar,videos,watch/providers"),
                URLQueryItem(name: "include_image_language", value: TMDBLocale.imageLanguages(for: locale)),
            ]
        )

        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: "Movie detail",
            sleeper: sleeper
        )

        do {
            let dto = try JSONDecoder().decode(MovieDetailDTO.self, from: data)
            let trailers = TMDBTrailerDecoding.trailers(from: data, logger: logger, context: "Movie detail")
            let streamingProviders = TMDBWatchProvidersDecoding.providers(
                from: data,
                locale: locale,
                logger: logger,
                context: "Movie detail"
            )
            return Self.map(
                dto,
                trailers: trailers,
                streamingProviders: streamingProviders,
                logger: logger
            )
        } catch let error as DecodingError {
            logger.error("Movie detail decode failed: \(error)", category: .networking)
            throw AppError.decoding
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("Movie detail decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    func collection(id: Int, locale: Locale = .current) async throws -> MovieCollection {
        let request = try requests.get(
            path: "collection/\(id)",
            queryItems: TMDBLocale.queryItems(locale: locale, page: 1).filter { $0.name != "page" }
        )

        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: "Collection",
            sleeper: sleeper
        )

        do {
            let dto = try JSONDecoder().decode(MovieCollectionDTO.self, from: data)
            let overview = dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return MovieCollection(
                id: dto.id,
                name: dto.name,
                overview: overview,
                posterPath: dto.posterPath,
                parts: (dto.parts ?? []).map(Self.map)
            )
        } catch let error as DecodingError {
            logger.error("Collection decode failed: \(error)", category: .networking)
            throw AppError.decoding
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("Collection decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    func movieReviews(id: Int, page: Int, locale: Locale = .current) async throws -> MovieReviewPage {
        let request = try requests.get(
            path: "movie/\(id)/reviews",
            queryItems: TMDBLocale.queryItems(locale: locale, page: page)
        )

        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: "Movie reviews",
            sleeper: sleeper
        )

        do {
            let decoded = try TMDBPageDecoding.decode(
                ReviewDTO.self,
                from: data,
                logger: logger,
                context: "Movie reviews"
            )
            let total = try Self.reviewTotalCount(from: data)
            let reviews = decoded.items.compactMap { Self.mapReview($0) }
            return MovieReviewPage(
                reviews: reviews,
                page: decoded.page,
                hasMore: decoded.page < decoded.totalPages,
                totalCount: total ?? reviews.count
            )
        } catch let error as DecodingError {
            logger.error("Movie reviews decode failed: \(error)", category: .networking)
            throw AppError.decoding
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("Movie reviews decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    // MARK: - Mapping

    static func map(_ dto: MovieSummaryDTO) -> Movie {
        Movie(
            id: dto.id,
            title: dto.title,
            posterPath: dto.posterPath,
            releaseDate: parseReleaseDate(dto.releaseDate),
            voteAverage: dto.voteAverage,
            genreIDs: dto.genreIDs,
            popularity: dto.popularity
        )
    }

    static func map(
        _ dto: MovieDetailDTO,
        trailers: [MediaTrailer],
        streamingProviders: [StreamingProvider] = [],
        logger: any AppLogging
    ) -> MovieDetail {
        MovieDetail(
            id: dto.id,
            title: dto.title,
            overview: dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            posterPath: dto.posterPath,
            releaseDate: parseReleaseDate(dto.releaseDate ?? ""),
            voteAverage: dto.voteAverage,
            popularity: dto.popularity ?? 0,
            genres: (dto.genres ?? []).map { MovieGenre(id: $0.id, name: $0.name) },
            trailers: trailers,
            streamingProviders: streamingProviders,
            budget: dto.budget ?? 0,
            revenue: dto.revenue ?? 0,
            images: mapImages(dto.images, logger: logger),
            cast: mapCast(dto.credits?.cast, logger: logger),
            crew: mapCrew(dto.credits?.crew, logger: logger),
            similar: mapSimilar(dto.similar?.results, logger: logger),
            collection: dto.belongsToCollection.map {
                MovieCollectionRef(id: $0.id, name: $0.name, posterPath: $0.posterPath)
            }
        )
    }

    static func mapImages(_ dto: MovieImagesDTO?, logger: any AppLogging) -> [MovieImage] {
        mapImageItems(dto?.backdrops, logger: logger)
    }

    /// Maps a TMDB image array (backdrops, stills, or posters), skipping blank paths.
    static func mapImageItems(
        _ items: [MovieImageDTO]?,
        logger: any AppLogging,
        limit: Int = 20
    ) -> [MovieImage] {
        guard let items else { return [] }
        var images: [MovieImage] = []
        var skipped = 0
        for item in items {
            let path = item.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                skipped += 1
                continue
            }
            images.append(MovieImage(filePath: path, voteAverage: item.voteAverage ?? 0))
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed movie image(s)", category: .networking)
        }
        return images
            .sorted { $0.voteAverage > $1.voteAverage }
            .prefix(limit)
            .map { $0 }
    }

    static func mapCast(_ items: [CastMemberDTO]?, logger: any AppLogging) -> [CastMember] {
        guard let items else { return [] }
        var cast: [CastMember] = []
        var skipped = 0
        for item in items {
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let creditID = item.creditID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, !creditID.isEmpty else {
                skipped += 1
                continue
            }
            let knownFor = item.knownForDepartment?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cast.append(
                CastMember(
                    id: creditID,
                    personID: item.id,
                    name: name,
                    character: item.character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    profilePath: item.profilePath,
                    order: item.order ?? Int.max,
                    knownForDepartment: (knownFor?.isEmpty == false) ? knownFor : nil
                )
            )
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed cast member(s)", category: .networking)
        }
        return cast
            .sorted { $0.order < $1.order }
            .prefix(20)
            .map { $0 }
    }

    static func mapCrew(_ items: [CrewMemberDTO]?, logger: any AppLogging) -> [CrewMember] {
        guard let items else { return [] }
        var crew: [CrewMember] = []
        var skipped = 0
        for item in items {
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let creditID = item.creditID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let job = item.job?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let department = item.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, !creditID.isEmpty, !job.isEmpty else {
                skipped += 1
                continue
            }
            let knownFor = item.knownForDepartment?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            crew.append(
                CrewMember(
                    id: creditID,
                    personID: item.id,
                    name: name,
                    job: job,
                    department: department,
                    profilePath: item.profilePath,
                    knownForDepartment: (knownFor?.isEmpty == false) ? knownFor : nil
                )
            )
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed crew member(s)", category: .networking)
        }
        return crew
    }

    /// Jobs that mean the person wrote the work. Assistants and coordinators stay off the list.
    static let writerJobs: Set<String> = ["Writer", "Screenplay", "Story", "Teleplay", "Author", "Novel"]

    /// Directors (`job == Director`) plus actual writing jobs, deduped by person id.
    static func creditedDirectorsAndWriters(from crew: [CrewMember]) -> [CreditedPerson] {
        var byPerson: [Int: CreditedPerson] = [:]
        var order: [Int] = []

        func append(member: CrewMember, role: String) {
            if var existing = byPerson[member.personID] {
                if !existing.roles.contains(role) {
                    existing = CreditedPerson(
                        id: existing.id,
                        name: existing.name,
                        roles: existing.roles + [role],
                        profilePath: existing.profilePath ?? member.profilePath,
                        knownForDepartment: existing.knownForDepartment ?? member.knownForDepartment
                    )
                    byPerson[member.personID] = existing
                }
            } else {
                byPerson[member.personID] = CreditedPerson(
                    id: member.personID,
                    name: member.name,
                    roles: [role],
                    profilePath: member.profilePath,
                    knownForDepartment: member.knownForDepartment
                )
                order.append(member.personID)
            }
        }

        for member in crew where member.job == "Director" {
            append(member: member, role: "Director")
        }
        for member in crew where writerJobs.contains(member.job) {
            append(member: member, role: member.job)
        }
        return order.compactMap { byPerson[$0] }
    }

    static func mapSimilar(_ items: [MovieSummaryDTO]?, logger: any AppLogging) -> [Movie] {
        guard let items else { return [] }
        var movies: [Movie] = []
        var skipped = 0
        var seen = Set<Int>()
        for item in items {
            let movie = map(item)
            guard seen.insert(movie.id).inserted else {
                skipped += 1
                continue
            }
            movies.append(movie)
            if movies.count == 20 { break }
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) duplicate similar movie(s)", category: .networking)
        }
        return movies
    }

    static func reviewTotalCount(from data: Data) throws -> Int? {
        try JSONDecoder().decode(ReviewPageMetaDTO.self, from: data).totalResults
    }

    static func mapReview(_ dto: ReviewDTO) -> MovieReview? {
        let content = dto.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        let author = dto.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Anonymous"
        let username = dto.authorDetails?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? author
        return MovieReview(
            id: dto.id,
            author: author,
            username: username,
            content: content,
            updatedAt: parseReviewDate(dto.updatedAt)
        )
    }

    static func parseReleaseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func parseReviewDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    static func decodeMovies(from data: Data, logger: any AppLogging) throws -> [Movie] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [Any] else {
            throw AppError.decoding
        }

        let decoder = JSONDecoder()
        var movies: [Movie] = []
        var skipped = 0

        for element in results {
            do {
                let elementData = try JSONSerialization.data(withJSONObject: element)
                let dto = try decoder.decode(MovieSummaryDTO.self, from: elementData)
                movies.append(map(dto))
            } catch {
                skipped += 1
            }
        }

        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed movie result(s)", category: .networking)
        }

        if movies.isEmpty, !results.isEmpty {
            throw AppError.decoding
        }

        return movies
    }
}

private struct MovieListPageMeta: Decodable {
    let page: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page
        case totalPages = "total_pages"
    }
}
