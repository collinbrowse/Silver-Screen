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
            castCredits: mapCastCredits(
                dto.combinedCredits?.cast,
                logger: logger,
                personName: dto.name
            ),
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

    /// Cast credits deduped by (mediaType, id), most recognizable roles first.
    /// `personName` catches one-off appearances where the character is the actor ("Jimmy Fallon"), not "Self".
    static func mapCastCredits(
        _ items: [PersonCombinedCreditDTO]?,
        logger: any AppLogging,
        personName: String = ""
    ) -> [PersonCredit] {
        guard let items else { return [] }
        var ranked: [RankedCredit] = []
        var seen = Set<String>()
        var skipped = 0

        for item in items {
            let character = item.character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let credit = mapCredit(item, roleOverride: character, logger: logger) else {
                skipped += 1
                continue
            }
            guard seen.insert(credit.id).inserted else {
                skipped += 1
                continue
            }
            ranked.append(RankedCredit(credit: credit, signals: signals(from: item)))
        }

        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed/duplicate cast credit(s)", category: .networking)
        }

        return sortByNotability(ranked, personName: personName, weighsPerformance: true)
    }

    /// Crew credits merged by (mediaType, id) with jobs joined, most recognizable titles first.
    static func mapCrewCredits(
        _ items: [PersonCombinedCreditDTO]?,
        logger: any AppLogging
    ) -> [PersonCredit] {
        guard let items else { return [] }
        var byKey: [String: RankedCredit] = [:]
        var order: [String] = []
        var skipped = 0

        for item in items {
            let job = item.job?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !job.isEmpty else {
                skipped += 1
                continue
            }
            guard let credit = mapCredit(item, roleOverride: job, logger: logger) else {
                skipped += 1
                continue
            }
            let incoming = signals(from: item)
            if var existing = byKey[credit.id] {
                if !existing.credit.roleLabel.split(separator: ", ").map(String.init).contains(job) {
                    existing.credit = PersonCredit(
                        mediaType: existing.credit.mediaType,
                        mediaID: existing.credit.mediaID,
                        title: existing.credit.title,
                        posterPath: existing.credit.posterPath ?? credit.posterPath,
                        releaseDate: existing.credit.releaseDate ?? credit.releaseDate,
                        genreIDs: existing.credit.genreIDs.isEmpty ? credit.genreIDs : existing.credit.genreIDs,
                        roleLabel: existing.credit.roleLabel + ", " + job,
                        popularity: max(existing.credit.popularity, credit.popularity),
                        voteAverage: max(existing.credit.voteAverage, credit.voteAverage)
                    )
                    existing.signals = existing.signals.merging(incoming)
                    byKey[credit.id] = existing
                }
            } else {
                byKey[credit.id] = RankedCredit(credit: credit, signals: incoming)
                order.append(credit.id)
            }
        }

        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed crew credit(s)", category: .networking)
        }

        let ranked = order.compactMap { byKey[$0] }
        return sortByNotability(ranked, personName: "", weighsPerformance: false)
    }

    private static func mapCredit(
        _ item: PersonCombinedCreditDTO,
        roleOverride: String?,
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
            popularity: item.popularity ?? 0,
            voteAverage: item.voteAverage ?? 0
        )
    }

    /// Vote count, billing, and episode count used to decide if a credit is a role the person is known for.
    private struct CreditSignals: Sendable {
        var voteCount: Int
        /// Nil when TMDB omitted call-sheet order. Treated as top billing so a missing field does not bury the credit.
        var billingOrder: Int?
        var episodeCount: Int?

        func merging(_ other: CreditSignals) -> CreditSignals {
            let episodes: Int?
            switch (episodeCount, other.episodeCount) {
            case let (left?, right?): episodes = max(left, right)
            case let (left?, nil): episodes = left
            case let (nil, right?): episodes = right
            case (nil, nil): episodes = nil
            }
            return CreditSignals(
                voteCount: max(voteCount, other.voteCount),
                billingOrder: billingOrder ?? other.billingOrder,
                episodeCount: episodes
            )
        }
    }

    /// A mapped credit plus the fields that rank it ahead of a merely popular title.
    private struct RankedCredit {
        var credit: PersonCredit
        var signals: CreditSignals
    }

    private static func signals(from item: PersonCombinedCreditDTO) -> CreditSignals {
        CreditSignals(
            voteCount: max(item.voteCount ?? 0, 0),
            billingOrder: item.order,
            episodeCount: item.episodeCount
        )
    }

    /// Recognizable roles first. Popularity only breaks ties, so a show that is airing this week
    /// does not outrank the film an actor is known for.
    private static func sortByNotability(
        _ ranked: [RankedCredit],
        personName: String,
        weighsPerformance: Bool
    ) -> [PersonCredit] {
        ranked.sorted { lhs, rhs in
            let left = notability(of: lhs, personName: personName, weighsPerformance: weighsPerformance)
            let right = notability(of: rhs, personName: personName, weighsPerformance: weighsPerformance)
            if left != right { return left > right }
            if lhs.credit.popularity != rhs.credit.popularity {
                return lhs.credit.popularity > rhs.credit.popularity
            }
            let title = lhs.credit.title.localizedStandardCompare(rhs.credit.title)
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.credit.mediaID < rhs.credit.mediaID
        }
        .map(\.credit)
    }

    /// How strongly this credit is "what they're known for."
    /// Leading movie roles keep the title's vote count, scaled down the call sheet.
    /// One TV appearance counts as a guest spot. A long run can outweigh a thin vote total,
    /// and a one-off "as themselves" credit (talk shows, cameos billed under the actor's name) is discounted.
    private static func notability(
        of ranked: RankedCredit,
        personName: String,
        weighsPerformance: Bool
    ) -> Double {
        let votes = Double(ranked.signals.voteCount)
        guard votes > 0 else { return 0 }

        let billed = weighsPerformance ? billingWeight(ranked.signals.billingOrder) : 1
        guard ranked.credit.mediaType == .tv else { return votes * billed }

        let episodes = max(ranked.signals.episodeCount ?? 1, 1)
        let guest = weighsPerformance
            && isBriefSelfAppearance(
                roleLabel: ranked.credit.roleLabel,
                personName: personName,
                episodeCount: episodes
            ) ? 0.2 : 1
        return votes * episodeWeight(episodes) * guest * billed
    }

    /// Top billing keeps the full vote count. Each step down the call sheet reduces it.
    /// Unknown or leading billing (`nil` or `0`) stays at full weight.
    private static func billingWeight(_ order: Int?) -> Double {
        guard let order, order > 0 else { return 1 }
        return 1 / Double(order + 1)
    }

    /// A single episode is a guest spot. About fifteen episodes match a movie.
    /// Very long runs cap at 2.5 so a daily show can surface for its host without burying a famous film.
    private static func episodeWeight(_ episodes: Int) -> Double {
        if episodes <= 1 { return 0.15 }
        return min(2.5, log2(Double(episodes) + 1) / log2(16))
    }

    /// Talk-show spots and one-episode cameos where the person plays themself.
    /// A host with a long episode count is left alone; that show is the role.
    private static func isBriefSelfAppearance(
        roleLabel: String,
        personName: String,
        episodeCount: Int
    ) -> Bool {
        guard episodeCount <= 2 else { return false }
        let role = roleLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !role.isEmpty else { return false }
        let markers = ["self", "himself", "herself", "themselves"]
        if markers.contains(where: { marker in
            role == marker
                || role.hasPrefix(marker + " ")
                || role.hasPrefix(marker + "-")
                || role.hasPrefix(marker + "—")
        }) {
            return true
        }
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard name.count >= 3 else { return false }
        return role.contains(name)
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
