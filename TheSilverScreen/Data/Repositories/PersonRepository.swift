//
//  PersonRepository.swift
//  TheSilverScreen
//

import Foundation

/// Loads person detail (bio, images, combined movie/TV credits, external ids) from TMDB.
final class PersonRepository: Sendable {
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

    /// Fetches person detail with `combined_credits`, `images`, and `external_ids` appended.
    func personDetail(id: Int, locale: Locale = .current) async throws -> PersonDetail {
        let request = try requests.get(
            path: "person/\(id)",
            queryItems: [
                URLQueryItem(name: "language", value: TMDBLocale.languageTag(for: locale)),
                URLQueryItem(name: "append_to_response", value: "combined_credits,images,external_ids"),
            ]
        )

        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: "Person detail",
            sleeper: sleeper
        )

        do {
            let dto = try JSONDecoder().decode(PersonDetailDTO.self, from: data)
            return Self.map(dto, logger: logger)
        } catch let error as DecodingError {
            logger.error("Person detail decode failed: \(error)", category: .networking)
            throw AppError.decoding
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("Person detail decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    /// Popular people for the Search tab's People segment.
    func popular(page: Int, locale: Locale = .current) async throws -> PersonPage {
        try await fetchPeoplePage(
            path: "person/popular",
            context: "Popular people",
            page: page,
            extra: [],
            locale: locale
        )
    }

    /// People search. The query is a request parameter and is never logged.
    func search(query: String, page: Int, locale: Locale = .current) async throws -> PersonPage {
        try await fetchPeoplePage(
            path: "search/person",
            context: "People search",
            page: page,
            extra: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: "false"),
            ],
            locale: locale
        )
    }

    private func fetchPeoplePage(
        path: String,
        context: String,
        page: Int,
        extra: [URLQueryItem],
        locale: Locale? = nil
    ) async throws -> PersonPage {
        let queryItems = TMDBLocale.queryItems(locale: locale ?? .current, page: page, extra: extra)
        let request = try requests.get(
            path: path,
            queryItems: queryItems
        )
        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: context,
            sleeper: sleeper
        )
        do {
            let decoded = try TMDBPageDecoding.decode(
                PersonSummaryDTO.self,
                from: data,
                logger: logger,
                context: context
            )
            let people = decoded.items.compactMap(Self.mapSummary)
            if people.isEmpty, !decoded.items.isEmpty {
                throw AppError.decoding
            }
            return PersonPage(
                people: people,
                page: decoded.page,
                hasMore: decoded.page < decoded.totalPages
            )
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("\(context) decode failed", category: .networking)
            throw AppError.decoding
        }
    }

    static func mapSummary(_ dto: PersonSummaryDTO) -> PersonSummary? {
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let department = dto.knownForDepartment?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonSummary(
            id: dto.id,
            name: name,
            profilePath: dto.profilePath,
            knownForDepartment: (department?.isEmpty == false) ? department : nil,
            popularity: dto.popularity ?? 0
        )
    }

    // MARK: - Mapping

    static func map(_ dto: PersonDetailDTO, logger: any AppLogging) -> PersonDetail {
        let knownFor = dto.knownForDepartment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let imdb = dto.externalIds?.imdbID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonDetail(
            id: dto.id,
            name: dto.name.trimmingCharacters(in: .whitespacesAndNewlines),
            biography: dto.biography?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            birthday: parseDay(dto.birthday),
            deathday: parseDay(dto.deathday),
            placeOfBirth: trimmedNonEmpty(dto.placeOfBirth),
            profilePath: dto.profilePath,
            knownForDepartment: (knownFor?.isEmpty == false) ? knownFor : nil,
            imdbID: (imdb?.isEmpty == false) ? imdb : nil,
            images: mapProfileImages(dto.images, logger: logger),
            castCredits: mapCastCredits(dto.combinedCredits?.cast, logger: logger),
            crewCredits: mapCrewCredits(dto.combinedCredits?.crew, logger: logger),
            popularity: dto.popularity ?? 0
        )
    }

    static func mapProfileImages(_ dto: PersonImagesDTO?, logger: any AppLogging) -> [MovieImage] {
        guard let profiles = dto?.profiles else { return [] }
        var images: [MovieImage] = []
        var skipped = 0
        for item in profiles {
            let path = item.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                skipped += 1
                continue
            }
            images.append(MovieImage(filePath: path, voteAverage: item.voteAverage ?? 0))
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed person image(s)", category: .networking)
        }
        return images
            .sorted { $0.voteAverage > $1.voteAverage }
            .prefix(20)
            .map { $0 }
    }

    /// Cast credits deduped by (mediaType, id), ordered by popularity descending.
    static func mapCastCredits(
        _ items: [PersonCombinedCreditDTO]?,
        logger: any AppLogging
    ) -> [PersonCredit] {
        guard let items else { return [] }
        var credits: [PersonCredit] = []
        var seen = Set<String>()
        var skipped = 0

        for item in items {
            guard let credit = mapCredit(item, roleOverride: nil, logger: logger) else {
                skipped += 1
                continue
            }
            guard seen.insert(credit.id).inserted else {
                skipped += 1
                continue
            }
            let character = item.character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            credits.append(
                PersonCredit(
                    mediaType: credit.mediaType,
                    mediaID: credit.mediaID,
                    title: credit.title,
                    posterPath: credit.posterPath,
                    releaseDate: credit.releaseDate,
                    genreIDs: credit.genreIDs,
                    roleLabel: character,
                    popularity: credit.popularity,
                    voteAverage: credit.voteAverage
                )
            )
        }

        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed/duplicate cast credit(s)", category: .networking)
        }

        return credits.sorted { $0.popularity > $1.popularity }
    }

    /// Crew credits merged by (mediaType, id) with jobs joined, ordered by popularity descending.
    static func mapCrewCredits(
        _ items: [PersonCombinedCreditDTO]?,
        logger: any AppLogging
    ) -> [PersonCredit] {
        guard let items else { return [] }
        var byKey: [String: PersonCredit] = [:]
        var order: [String] = []
        var skipped = 0

        for item in items {
            let job = item.job?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !job.isEmpty else {
                skipped += 1
                continue
            }
            let department = item.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let creditJob = PersonCreditJob(department: department, job: job)
            guard let credit = mapCredit(item, roleOverride: job, jobs: [creditJob], logger: logger) else {
                skipped += 1
                continue
            }
            if var existing = byKey[credit.id] {
                if !existing.jobs.contains(where: { $0.job == job }) {
                    let jobs = existing.jobs + [creditJob]
                    existing = PersonCredit(
                        mediaType: existing.mediaType,
                        mediaID: existing.mediaID,
                        title: existing.title,
                        posterPath: existing.posterPath ?? credit.posterPath,
                        releaseDate: existing.releaseDate ?? credit.releaseDate,
                        genreIDs: existing.genreIDs.isEmpty ? credit.genreIDs : existing.genreIDs,
                        roleLabel: jobs.map(\.job).joined(separator: ", "),
                        jobs: jobs,
                        popularity: max(existing.popularity, credit.popularity),
                        voteAverage: max(existing.voteAverage, credit.voteAverage)
                    )
                    byKey[credit.id] = existing
                }
            } else {
                byKey[credit.id] = credit
                order.append(credit.id)
            }
        }

        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed crew credit(s)", category: .networking)
        }

        return order
            .compactMap { byKey[$0] }
            .sorted { $0.popularity > $1.popularity }
    }

    private static func mapCredit(
        _ item: PersonCombinedCreditDTO,
        roleOverride: String?,
        jobs: [PersonCreditJob] = [],
        logger: any AppLogging
    ) -> PersonCredit? {
        guard let mediaType = parseMediaType(item.mediaType) else { return nil }
        let title: String
        switch mediaType {
        case .movie:
            title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .tv:
            title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !title.isEmpty else { return nil }

        let dateRaw: String?
        switch mediaType {
        case .movie: dateRaw = item.releaseDate
        case .tv: dateRaw = item.firstAirDate
        }

        return PersonCredit(
            mediaType: mediaType,
            mediaID: item.id,
            title: title,
            posterPath: item.posterPath,
            releaseDate: parseDay(dateRaw),
            genreIDs: item.genreIDs ?? [],
            roleLabel: roleOverride ?? "",
            jobs: jobs,
            popularity: item.popularity ?? 0,
            voteAverage: item.voteAverage ?? 0
        )
    }

    private static func parseMediaType(_ raw: String?) -> CreditMediaType? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "movie": return .movie
        case "tv": return .tv
        default: return nil
        }
    }

    static func parseDay(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return MovieRepository.parseReleaseDate(raw)
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
