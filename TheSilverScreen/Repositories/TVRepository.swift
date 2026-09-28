//
//  TVRepository.swift
//  TheSilverScreen
//
//  TV series, season, and episode reads. Mapping, paging, and AppError
//  translation stay here so screens never see a DTO.
//

import Foundation

final class TVRepository: Sendable {
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

    /// One Discover page, already sorted. Browse merges this with the movie stream.
    func discover(
        sort: BrowseSort,
        window: BrowseWindow,
        page: Int,
        locale: Locale = .current,
        today: Date = Date(),
        timeZone: TimeZone = .current
    ) async throws -> TVSeriesPage {
        try await fetch(
            path: DiscoverKind.tv.path,
            context: "Browse TV",
            queryItems: DiscoverQuery.items(
                kind: .tv,
                sort: sort,
                window: window,
                page: page,
                locale: locale,
                today: today,
                timeZone: timeZone
            )
        ) { data in
            let decoded = try TMDBPageDecoding.decode(
                TVSeriesSummaryDTO.self,
                from: data,
                logger: logger,
                context: "Browse TV"
            )
            let series = decoded.items.compactMap { Self.mapSummary($0) }
            if series.isEmpty, !decoded.items.isEmpty {
                throw AppError.decoding
            }
            return TVSeriesPage(
                series: series,
                page: decoded.page,
                hasMore: decoded.page < decoded.totalPages
            )
        }
    }

    /// Shows with an episode on the air (`/tv/on_the_air`). The list is not sortable.
    func onTheAir(page: Int, locale: Locale = .current) async throws -> TVSeriesPage {
        try await fetchSeriesPage(
            path: "tv/on_the_air",
            context: "TV on the air",
            page: page,
            extra: [],
            locale: locale
        )
    }

    /// Series whose first episode airs after the user's local today.
    func upcoming(
        page: Int,
        locale: Locale = .current,
        today: Date = Date(),
        timeZone: TimeZone = .current
    ) async throws -> TVSeriesPage {
        let after = TMDBDay.string(from: TMDBDay.adding(days: 1, to: today, timeZone: timeZone), timeZone: timeZone)
        return try await fetchSeriesPage(
            path: DiscoverKind.tv.path,
            context: "Upcoming TV",
            page: page,
            extra: [
                URLQueryItem(name: "sort_by", value: "first_air_date.asc"),
                URLQueryItem(name: "first_air_date.gte", value: after),
            ],
            locale: locale
        )
    }

    func popular(page: Int, locale: Locale = .current) async throws -> TVSeriesPage {
        try await fetchSeriesPage(
            path: "tv/popular",
            context: "Popular TV",
            page: page,
            extra: [],
            locale: locale
        )
    }

    func search(query: String, page: Int, locale: Locale = .current) async throws -> TVSeriesPage {
        try await fetchSeriesPage(
            path: "search/tv",
            context: "TV search",
            page: page,
            extra: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: "false"),
            ],
            locale: locale
        )
    }

    /// Series in any of these genres, most popular first.
    func series(inGenres ids: [Int], page: Int, locale: Locale = .current) async throws -> TVSeriesPage {
        try await fetchSeriesPage(
            path: "discover/tv",
            context: "TV by genre",
            page: page,
            extra: [
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "with_genres", value: ids.map(String.init).joined(separator: "|")),
            ],
            locale: locale
        )
    }

    /// Series detail with images, aggregate credits, recommendations, and videos appended.
    /// Language follows the device. Appended sections decode on their own so one bad row
    /// cannot fail the screen.
    func series(id: Int, locale: Locale = .current) async throws -> TVSeriesDetail {
        try await fetch(
            path: "tv/\(id)",
            context: "TV series",
            queryItems: [
                URLQueryItem(name: "language", value: TMDBLocale.languageTag(for: locale)),
                URLQueryItem(name: "append_to_response", value: "images,aggregate_credits,recommendations,videos"),
                URLQueryItem(name: "include_image_language", value: TMDBLocale.imageLanguages(for: locale)),
            ]
        ) { data in
            try Self.decodeSeries(data, logger: logger)
        }
    }

    func season(seriesID: Int, seasonNumber: Int, locale: Locale = .current) async throws -> TVSeasonDetail {
        try await fetch(
            path: "tv/\(seriesID)/season/\(seasonNumber)",
            context: "TV season",
            queryItems: [
                URLQueryItem(name: "language", value: TMDBLocale.languageTag(for: locale)),
                URLQueryItem(name: "append_to_response", value: "images,aggregate_credits,videos"),
            ]
        ) { data in
            try Self.decodeSeason(data, logger: logger)
        }
    }

    func episode(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        locale: Locale = .current
    ) async throws -> TVEpisodeDetail {
        try await fetch(
            path: "tv/\(seriesID)/season/\(seasonNumber)/episode/\(episodeNumber)",
            context: "TV episode",
            queryItems: [
                URLQueryItem(name: "language", value: TMDBLocale.languageTag(for: locale)),
                URLQueryItem(name: "append_to_response", value: "images,credits,videos"),
            ]
        ) { data in
            try Self.decodeEpisode(data, logger: logger)
        }
    }

    func reviews(seriesID: Int, page: Int, locale: Locale = .current) async throws -> MovieReviewPage {
        try await fetch(
            path: "tv/\(seriesID)/reviews",
            context: "TV reviews",
            queryItems: TMDBLocale.queryItems(locale: locale, page: page)
        ) { data in
            let decoded = try TMDBPageDecoding.decode(
                ReviewDTO.self,
                from: data,
                logger: logger,
                context: "TV reviews"
            )
            let total = try MovieRepository.reviewTotalCount(from: data)
            let reviews = decoded.items.compactMap { MovieRepository.mapReview($0) }
            return MovieReviewPage(
                reviews: reviews,
                page: decoded.page,
                hasMore: decoded.page < decoded.totalPages,
                totalCount: total ?? reviews.count
            )
        }
    }

    // MARK: - Transport

    private func fetchSeriesPage(
        path: String,
        context: String,
        page: Int,
        extra: [URLQueryItem],
        locale: Locale? = nil
    ) async throws -> TVSeriesPage {
        let queryItems = TMDBLocale.queryItems(locale: locale ?? .current, page: page, extra: extra)
        return try await fetch(
            path: path,
            context: context,
            queryItems: queryItems
        ) { data in
            let decoded = try TMDBPageDecoding.decode(
                TVSeriesSummaryDTO.self,
                from: data,
                logger: logger,
                context: context
            )
            let series = decoded.items.compactMap { Self.mapSummary($0) }
            if series.isEmpty, !decoded.items.isEmpty {
                throw AppError.decoding
            }
            return TVSeriesPage(
                series: series,
                page: decoded.page,
                hasMore: decoded.page < decoded.totalPages
            )
        }
    }

    private func fetch<T: Sendable>(
        path: String,
        context: String,
        queryItems: [URLQueryItem],
        map: (Data) throws -> T
    ) async throws -> T {
        let request = try requests.get(path: path, queryItems: queryItems)
        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: context,
            sleeper: sleeper
        )
        do {
            return try map(data)
        } catch let error as DecodingError {
            logger.error("\(context) decode failed: \(error)", category: .networking)
            throw AppError.decoding
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("\(context) decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    // MARK: - Appended sections

    /// Core fields still fail the screen. A bad appended section is skipped and logged.
    private static func decodeSeries(_ data: Data, logger: any AppLogging) throws -> TVSeriesDetail {
        let dto = try JSONDecoder().decode(TVSeriesDetailDTO.self, from: data)
        logSkippedSections(dto.sectionFailures, context: "TV series", logger: logger)
        let images = imageItems(dto.images?.backdrops, logger: logger)
        let credits = aggregateCredits(dto.aggregateCredits, logger: logger)
        let recommendations = (dto.recommendations?.results ?? [])
            .compactMap(mapSummary)
            .filter { $0.id != dto.id }
            .prefix(20)
            .map { $0 }
        return mapSeries(
            dto,
            logger: logger,
            images: images,
            recommendations: recommendations,
            cast: credits.cast,
            directorsAndWriters: credits.crew,
            trailers: TMDBTrailerDecoding.trailers(from: data, logger: logger, context: "TV series")
        )
    }

    private static func decodeSeason(_ data: Data, logger: any AppLogging) throws -> TVSeasonDetail {
        let dto = try JSONDecoder().decode(TVSeasonDetailDTO.self, from: data)
        logSkippedSections(dto.sectionFailures, context: "TV season", logger: logger)
        let stills = dto.images?.stills ?? dto.images?.posters
        let images = imageItems(stills, logger: logger)
        let credits = aggregateCredits(dto.aggregateCredits, logger: logger)
        return mapSeason(
            dto,
            logger: logger,
            images: images,
            cast: credits.cast,
            directorsAndWriters: credits.crew,
            trailers: TMDBTrailerDecoding.trailers(from: data, logger: logger, context: "TV season")
        )
    }

    private static func decodeEpisode(_ data: Data, logger: any AppLogging) throws -> TVEpisodeDetail {
        let dto = try JSONDecoder().decode(TVEpisodeDetailDTO.self, from: data)
        logSkippedSections(dto.sectionFailures, context: "TV episode", logger: logger)
        let images = imageItems(dto.images?.stills, logger: logger)
        let credits = dto.credits
        let guests = (credits?.guestStars?.isEmpty == false ? credits?.guestStars : dto.guestStars) ?? []
        let crew = (credits?.crew?.isEmpty == false ? credits?.crew : dto.crew) ?? []
        return mapEpisode(
            dto,
            logger: logger,
            images: images,
            cast: credits?.cast ?? [],
            guestStars: guests,
            crew: crew,
            trailers: TMDBTrailerDecoding.trailers(from: data, logger: logger, context: "TV episode")
        )
    }

    private static func logSkippedSections(_ names: [String], context: String, logger: any AppLogging) {
        for name in names {
            logger.error("\(context) skipped malformed \(name)", category: .networking)
        }
    }

    private static func imageItems(_ items: [MovieImageDTO]?, logger: any AppLogging) -> [MovieImage] {
        MovieRepository.mapImageItems(items ?? [], logger: logger)
    }

    private static func aggregateCredits(
        _ dto: TVAggregateCreditsDTO?,
        logger: any AppLogging
    ) -> (cast: [TVCredit], crew: [TVCredit]) {
        guard let dto else { return ([], []) }
        return (
            mapAggregateCast(dto.cast, logger: logger),
            mapAggregateCrew(dto.crew, logger: logger)
        )
    }

    // MARK: - Mapping

    static func mapSummary(_ dto: TVSeriesSummaryDTO) -> TVSeriesSummary? {
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return TVSeriesSummary(
            id: dto.id,
            name: name,
            posterPath: dto.posterPath,
            firstAirDate: MovieRepository.parseReleaseDate(dto.firstAirDate ?? ""),
            genreIDs: dto.genreIDs ?? [],
            voteAverage: dto.voteAverage ?? 0,
            popularity: dto.popularity ?? 0
        )
    }

    static func mapSeries(
        _ dto: TVSeriesDetailDTO,
        logger: any AppLogging,
        images: [MovieImage],
        recommendations: [TVSeriesSummary],
        cast: [TVCredit],
        directorsAndWriters: [TVCredit],
        trailers: [MediaTrailer]
    ) -> TVSeriesDetail {
        let creators = (dto.createdBy ?? []).compactMap { creator -> String? in
            let name = creator.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
        let seasons = (dto.seasons ?? [])
            .map { mapSeasonSummary($0) }
            .sorted { $0.seasonNumber < $1.seasonNumber }
        return TVSeriesDetail(
            id: dto.id,
            name: dto.name.trimmingCharacters(in: .whitespacesAndNewlines),
            overview: dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            posterPath: dto.posterPath,
            firstAirDate: MovieRepository.parseReleaseDate(dto.firstAirDate ?? ""),
            lastAirDate: MovieRepository.parseReleaseDate(dto.lastAirDate ?? ""),
            genres: (dto.genres ?? []).map { MovieGenre(id: $0.id, name: $0.name) },
            trailers: trailers,
            voteAverage: dto.voteAverage ?? 0,
            popularity: dto.popularity ?? 0,
            creators: creators,
            images: images,
            seasons: seasons,
            recommendations: recommendations,
            cast: cast,
            directorsAndWriters: directorsAndWriters
        )
    }

    static func mapSeason(
        _ dto: TVSeasonDetailDTO,
        logger: any AppLogging,
        images: [MovieImage],
        cast: [TVCredit],
        directorsAndWriters: [TVCredit],
        trailers: [MediaTrailer]
    ) -> TVSeasonDetail {
        let episodes = (dto.episodes ?? [])
            .sorted { $0.episodeNumber < $1.episodeNumber }
            .map { mapEpisodeSummary($0, logger: logger) }
        return TVSeasonDetail(
            id: dto.id,
            name: dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            seasonNumber: dto.seasonNumber,
            overview: dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            airDate: MovieRepository.parseReleaseDate(dto.airDate ?? ""),
            posterPath: dto.posterPath,
            voteAverage: dto.voteAverage ?? 0,
            images: images,
            cast: cast,
            directorsAndWriters: directorsAndWriters,
            episodes: episodes,
            trailers: trailers
        )
    }

    static func mapEpisode(
        _ dto: TVEpisodeDetailDTO,
        logger: any AppLogging,
        images: [MovieImage],
        cast: [CastMemberDTO],
        guestStars: [CastMemberDTO],
        crew: [CrewMemberDTO],
        trailers: [MediaTrailer]
    ) -> TVEpisodeDetail {
        TVEpisodeDetail(
            id: dto.id,
            title: dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            episodeNumber: dto.episodeNumber,
            overview: dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            airDate: MovieRepository.parseReleaseDate(dto.airDate ?? ""),
            stillPath: dto.stillPath,
            voteAverage: dto.voteAverage ?? 0,
            images: images,
            cast: mapEpisodePeople(cast, logger: logger, context: "episode cast"),
            guestStars: mapEpisodePeople(guestStars, logger: logger, context: "guest stars"),
            directorsAndWriters: mapEpisodeCrew(crew, logger: logger),
            trailers: trailers
        )
    }

    /// Cast with a real episode count, highest first, then name. At most 30 people.
    static func mapAggregateCast(
        _ items: [TVAggregateCastDTO]?,
        logger: any AppLogging
    ) -> [TVCredit] {
        guard let items else { return [] }
        var credits: [TVCredit] = []
        var seen = Set<Int>()
        var skipped = 0
        for item in items {
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, seen.insert(item.id).inserted else {
                skipped += 1
                continue
            }
            let character = (item.roles ?? [])
                .sorted { ($0.episodeCount ?? 0) > ($1.episodeCount ?? 0) }
                .compactMap { role -> String? in
                    let value = role.character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return value.isEmpty ? nil : value
                }
                .first ?? ""
            let knownFor = trimmed(item.knownForDepartment)
            credits.append(
                TVCredit(
                    id: item.id,
                    name: name,
                    role: character,
                    profilePath: item.profilePath,
                    episodeCount: item.totalEpisodeCount ?? 0,
                    knownForDepartment: knownFor
                )
            )
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed aggregate cast credit(s)", category: .networking)
        }
        return rankedByEpisodeCount(credits)
    }

    /// Directors and writing-department crew with a real episode count, then name. At most 30.
    static func mapAggregateCrew(
        _ items: [TVAggregateCrewDTO]?,
        logger: any AppLogging
    ) -> [TVCredit] {
        guard let items else { return [] }
        var byPerson: [Int: TVCredit] = [:]
        var skipped = 0
        for item in items {
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else {
                skipped += 1
                continue
            }
            let roles = directorAndWriterRoles(jobs: item.jobs ?? [])
            guard !roles.isEmpty else { continue }
            let credit = TVCredit(
                id: item.id,
                name: name,
                role: roles.joined(separator: ", "),
                profilePath: item.profilePath,
                episodeCount: item.totalEpisodeCount ?? 0,
                knownForDepartment: trimmed(item.knownForDepartment)
            )
            if let existing = byPerson[item.id] {
                let mergedRoles = mergeRoles(existing.role, credit.role)
                byPerson[item.id] = TVCredit(
                    id: item.id,
                    name: existing.name,
                    role: mergedRoles,
                    profilePath: existing.profilePath ?? credit.profilePath,
                    episodeCount: max(existing.episodeCount, credit.episodeCount),
                    knownForDepartment: existing.knownForDepartment ?? credit.knownForDepartment
                )
            } else {
                byPerson[item.id] = credit
            }
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed aggregate crew credit(s)", category: .networking)
        }
        return rankedByEpisodeCount(Array(byPerson.values))
    }

    private static func mapSeasonSummary(_ dto: TVSeasonSummaryDTO) -> TVSeasonSummary {
        TVSeasonSummary(
            id: dto.id,
            name: dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            seasonNumber: dto.seasonNumber,
            episodeCount: dto.episodeCount ?? 0,
            airDate: MovieRepository.parseReleaseDate(dto.airDate ?? ""),
            posterPath: dto.posterPath
        )
    }

    private static func mapEpisodeSummary(
        _ dto: TVEpisodeSummaryDTO,
        logger: any AppLogging
    ) -> TVEpisodeSummary {
        let crew = MovieRepository.mapCrew(dto.crew, logger: logger)
        let directors = crew.filter { $0.job == "Director" }.map(\.name)
        let director = directors.isEmpty ? nil : directors.joined(separator: ", ")
        return TVEpisodeSummary(
            id: dto.id,
            title: dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            episodeNumber: dto.episodeNumber,
            overview: dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            airDate: MovieRepository.parseReleaseDate(dto.airDate ?? ""),
            stillPath: dto.stillPath,
            directorName: director
        )
    }

    private static func mapEpisodePeople(
        _ items: [CastMemberDTO],
        logger: any AppLogging,
        context: String
    ) -> [TVCredit] {
        let members = MovieRepository.mapCast(items, logger: logger)
        var seen = Set<Int>()
        var credits: [TVCredit] = []
        for member in members where seen.insert(member.personID).inserted {
            credits.append(
                TVCredit(
                    id: member.personID,
                    name: member.name,
                    role: member.character,
                    profilePath: member.profilePath,
                    episodeCount: 0,
                    knownForDepartment: member.knownForDepartment
                )
            )
            if credits.count == 30 { break }
        }
        if members.count > credits.count {
            logger.error("Capped \(context) at 30 people", category: .networking)
        }
        return credits
    }

    /// Episode crew keeps directors and the shared writer jobs. Other writing roles stay off the list.
    private static func mapEpisodeCrew(
        _ items: [CrewMemberDTO],
        logger: any AppLogging
    ) -> [TVCredit] {
        let allowed = MovieRepository.writerJobs.union(["Director"])
        let crew = MovieRepository.mapCrew(items, logger: logger).filter { allowed.contains($0.job) }
        var rolesByPerson: [Int: [String]] = [:]
        var creditByPerson: [Int: TVCredit] = [:]
        var order: [Int] = []
        for member in crew {
            if rolesByPerson[member.personID] == nil {
                order.append(member.personID)
                rolesByPerson[member.personID] = [member.job]
                creditByPerson[member.personID] = TVCredit(
                    id: member.personID,
                    name: member.name,
                    role: member.job,
                    profilePath: member.profilePath,
                    episodeCount: 0,
                    knownForDepartment: member.knownForDepartment
                )
            } else if rolesByPerson[member.personID]?.contains(member.job) == false {
                rolesByPerson[member.personID, default: []].append(member.job)
            }
        }
        return order.prefix(30).compactMap { id in
            guard let credit = creditByPerson[id], let roles = rolesByPerson[id] else { return nil }
            return TVCredit(
                id: credit.id,
                name: credit.name,
                role: roles.joined(separator: ", "),
                profilePath: credit.profilePath,
                episodeCount: 0,
                knownForDepartment: credit.knownForDepartment
            )
        }
    }

    /// Drops people who never appeared, then orders by count, name, and id.
    private static func rankedByEpisodeCount(_ credits: [TVCredit]) -> [TVCredit] {
        Array(
            credits
                .filter { $0.episodeCount > 0 }
                .sorted(by: byEpisodeCountThenName)
                .prefix(30)
        )
    }

    private static func byEpisodeCountThenName(_ lhs: TVCredit, _ rhs: TVCredit) -> Bool {
        if lhs.episodeCount != rhs.episodeCount {
            return lhs.episodeCount > rhs.episodeCount
        }
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order != .orderedSame {
            return order == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func directorAndWriterRoles(
        jobs: [TVAggregateJobDTO]
    ) -> [String] {
        var roles: [String] = []
        if jobs.contains(where: { $0.job == "Director" }) {
            roles.append("Director")
        }
        for job in jobs {
            let title = job.job?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard MovieRepository.writerJobs.contains(title), !roles.contains(title) else { continue }
            roles.append(title)
        }
        return roles
    }

    private static func mergeRoles(_ lhs: String, _ rhs: String) -> String {
        var roles = lhs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for role in rhs.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !roles.contains(role) {
            roles.append(role)
        }
        return roles.joined(separator: ", ")
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
