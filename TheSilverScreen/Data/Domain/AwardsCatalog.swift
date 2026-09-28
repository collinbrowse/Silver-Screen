//
//  AwardsCatalog.swift
//  TheSilverScreen
//
//  Bundled award credits. Shelves and detail pills read this file; the weekly
//  job rebuilds it from Wikidata and leaves already-resolved TMDB ids in place.
//

import Foundation

/// Prize body stored in the catalog. New bodies are another case plus a builder entry.
enum AwardFamily: String, Codable, Hashable, Sendable, CaseIterable {
    case academy
    case bafta
    case emmy

    /// Name on the search shelf and the category screen.
    var title: String {
        switch self {
        case .academy: "Oscar Winners"
        case .bafta: "BAFTAs"
        case .emmy: "Emmys"
        }
    }

    var subtitle: String {
        switch self {
        case .academy: "Academy Awards"
        case .bafta: "Film categories"
        case .emmy: "Primetime categories"
        }
    }

    /// Search-card lockup. BAFTA and Emmy include a dark-mode variant in the asset.
    var shelfImage: String {
        switch self {
        case .academy: "AwardShelfOscar"
        case .bafta: "AwardShelfBafta"
        case .emmy: "AwardShelfEmmy"
        }
    }

    /// Asset catalog image of this prize’s trophy.
    var trophyImage: String {
        switch self {
        case .academy: "AwardOscar"
        case .bafta: "AwardBafta"
        case .emmy: "AwardEmmy"
        }
    }

    /// Width divided by height of `trophyImage`, so a pill can size the picture.
    var trophyAspect: Double {
        switch self {
        case .academy: 0.34
        case .bafta: 0.47
        case .emmy: 0.64
        }
    }

    /// Spoken beside a category. The trophy is decorative, so VoiceOver needs this name.
    var shortName: String {
        switch self {
        case .academy: "Oscar"
        case .bafta: "BAFTA"
        case .emmy: "Emmy"
        }
    }
}

/// One detail pill: which prize the trophy depicts, and the words beside it.
struct AwardPill: Hashable, Sendable, Identifiable {
    var family: AwardFamily
    /// Category name, or “category nominee” when the title has no wins.
    var title: String

    var id: String { "\(family.rawValue)|\(title)" }

    /// Prize body plus category. Nominations keep the word “nominee”.
    var accessibilityName: String {
        let nominee = " nominee"
        if title.hasSuffix(nominee) {
            let category = title.dropLast(nominee.count)
            return "\(family.shortName) nominee for \(category)"
        }
        return "\(family.shortName) for \(title)"
    }
}

/// How a credit is opened. Matches the ids detail screens already use.
struct AwardWork: Codable, Hashable, Sendable, Equatable {
    enum Kind: String, Codable, Hashable, Sendable {
        case movie
        case series
        case season
        case episode
    }

    var kind: Kind
    var movieID: Int?
    var seriesID: Int?
    /// Eyebrow on season and episode screens. Empty when TMDB did not return a name.
    var seriesName: String?
    var seasonNumber: Int?
    var episodeNumber: Int?

    func matches(movieID: Int) -> Bool {
        kind == .movie && self.movieID == movieID
    }

    func matches(seriesID: Int) -> Bool {
        kind == .series && self.seriesID == seriesID
    }

    func matches(seriesID: Int, seasonNumber: Int) -> Bool {
        kind == .season && self.seriesID == seriesID && self.seasonNumber == seasonNumber
    }

    func matches(seriesID: Int, seasonNumber: Int, episodeNumber: Int) -> Bool {
        kind == .episode
            && self.seriesID == seriesID
            && self.seasonNumber == seasonNumber
            && self.episodeNumber == episodeNumber
    }

    /// Route for this work, or nil when the TMDB id never resolved.
    func route(fallbackSeriesName: String) -> Route? {
        switch kind {
        case .movie:
            guard let movieID else { return nil }
            return .movieDetail(id: movieID)
        case .series:
            guard let seriesID else { return nil }
            return .tvSeries(id: seriesID)
        case .season:
            guard let seriesID, let seasonNumber else { return nil }
            return .tvSeason(
                seriesID: seriesID,
                seriesName: displaySeriesName(fallback: fallbackSeriesName),
                seasonNumber: seasonNumber
            )
        case .episode:
            guard let seriesID, let seasonNumber, let episodeNumber else { return nil }
            return .tvEpisode(
                seriesID: seriesID,
                seriesName: displaySeriesName(fallback: fallbackSeriesName),
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
        }
    }

    private func displaySeriesName(fallback: String) -> String {
        if let seriesName, !seriesName.isEmpty { return seriesName }
        return fallback
    }
}

/// Someone a prize was given to. Title awards such as Best Picture have none.
struct AwardRecipient: Codable, Hashable, Sendable, Equatable {
    let name: String
    let wikidataID: String
    /// IMDb name id (`nm…`). Person screens match on this.
    let imdbID: String?
}

/// One nomination or win. `key` is stable across weekly rebuilds so resolved ids are reused.
struct AwardCredit: Codable, Hashable, Sendable, Equatable, Identifiable {
    let key: String
    let family: AwardFamily
    let category: String
    let categoryID: String
    let won: Bool
    let year: Int
    /// Display title used to order and to label a row before TMDB hydration.
    let title: String
    let imdbID: String?
    let wikidataID: String?
    let work: AwardWork?
    /// People this prize names. Empty when the prize belongs to the title.
    let recipients: [AwardRecipient]

    var id: String { key }

    init(
        key: String,
        family: AwardFamily,
        category: String,
        categoryID: String,
        won: Bool,
        year: Int,
        title: String,
        imdbID: String?,
        wikidataID: String?,
        work: AwardWork?,
        recipients: [AwardRecipient] = []
    ) {
        self.key = key
        self.family = family
        self.category = category
        self.categoryID = categoryID
        self.won = won
        self.year = year
        self.title = title
        self.imdbID = imdbID
        self.wikidataID = wikidataID
        self.work = work
        self.recipients = recipients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        family = try container.decode(AwardFamily.self, forKey: .family)
        category = try container.decode(String.self, forKey: .category)
        categoryID = try container.decode(String.self, forKey: .categoryID)
        won = try container.decode(Bool.self, forKey: .won)
        year = try container.decode(Int.self, forKey: .year)
        title = try container.decode(String.self, forKey: .title)
        imdbID = try container.decodeIfPresent(String.self, forKey: .imdbID)
        wikidataID = try container.decodeIfPresent(String.self, forKey: .wikidataID)
        work = try container.decodeIfPresent(AwardWork.self, forKey: .work)
        recipients = try container.decodeIfPresent([AwardRecipient].self, forKey: .recipients) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(family, forKey: .family)
        try container.encode(category, forKey: .category)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(won, forKey: .won)
        try container.encode(year, forKey: .year)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(imdbID, forKey: .imdbID)
        try container.encodeIfPresent(wikidataID, forKey: .wikidataID)
        try container.encodeIfPresent(work, forKey: .work)
        if !recipients.isEmpty {
            try container.encode(recipients, forKey: .recipients)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case key, family, category, categoryID, won, year, title, imdbID, wikidataID, work, recipients
    }
}

/// A prize given to a person for a specific title.
struct PersonAward: Hashable, Sendable, Equatable, Identifiable {
    let key: String
    let family: AwardFamily
    let category: String
    let won: Bool
    let year: Int
    let workTitle: String
    /// Detail screen for the title, when the catalog resolved a TMDB id.
    let route: Route?

    var id: String { key }

    /// Category name. Nominations keep the word "nominee", same as a title pill.
    var categoryLabel: String {
        won ? category : "\(category) nominee"
    }

    /// Movie or episode, then the ceremony year.
    var workLine: String {
        "\(workTitle) · \(year)"
    }

    /// Prize body, category, title, and year. The trophy is decorative.
    var accessibilityName: String {
        let prize = won
            ? "\(family.shortName) for \(category)"
            : "\(family.shortName) nominee for \(category)"
        return "\(prize), \(workTitle), \(year)"
    }
}

/// The JSON document in the bundle and in Application Support.
struct AwardsCatalog: Codable, Equatable, Sendable {
    var generatedAt: Date
    var credits: [AwardCredit]

    static let empty = AwardsCatalog(generatedAt: .distantPast, credits: [])

    static func decode(from data: Data) throws -> AwardsCatalog {
        try AwardJSON.decoder().decode(AwardsCatalog.self, from: data)
    }

    func encoded() throws -> Data {
        try AwardJSON.encoder().encode(self)
    }
}

/// Which credits a title list shows. A nil category is every category in the family.
struct AwardTitleRequest: Hashable, Codable, Sendable, Equatable {
    var family: AwardFamily?
    var category: String?

    var navigationTitle: String {
        if let category, !category.isEmpty { return category }
        switch family {
        case .academy: return "Oscar Winners"
        case .bafta: return "BAFTAs"
        case .emmy: return "Emmys"
        case nil: return "Awards"
        }
    }
}

/// Search-home card. The list is fixed; category screens discover categories from the file.
struct AwardShelf: Identifiable, Hashable, Sendable, Equatable {
    enum Destination: Hashable, Sendable {
        case family(AwardFamily)
        case titles(AwardTitleRequest)
    }

    let id: String
    let title: String
    let subtitle: String
    let destination: Destination

    /// Prize body when this card opens a family. Title shelves have none.
    var family: AwardFamily? {
        if case .family(let family) = destination { return family }
        return nil
    }

    /// Family cards only. Each one opens that body's categories.
    static let home: [AwardShelf] = AwardFamily.allCases.map { family in
        AwardShelf(
            id: family.rawValue,
            title: family.title,
            subtitle: family.subtitle,
            destination: .family(family)
        )
    }
}

/// A category row on a family screen.
struct AwardCategory: Identifiable, Hashable, Sendable, Equatable {
    let name: String
    var id: String { name }
}

struct AwardCreditPage: Sendable, Equatable {
    let credits: [AwardCredit]
    let page: Int
    let hasMore: Bool
}

/// Win and nomination pills. Wins replace nominations; the trophy is never the only signal.
enum AwardPillCopy {
    static let nominationLimit = 3

    static func labels(from credits: [AwardCredit]) -> [AwardPill] {
        let wins = uniqueCategories(credits.filter(\.won))
        if !wins.isEmpty {
            return wins.map { AwardPill(family: $0.family, title: $0.category) }
        }
        return uniqueCategories(credits.filter { !$0.won })
            .prefix(nominationLimit)
            .map { AwardPill(family: $0.family, title: "\($0.category) nominee") }
    }

    /// Newest ceremony first. One pill per prize body and category, so two bodies
    /// that share a name (Best Actor) each keep a trophy.
    private static func uniqueCategories(_ credits: [AwardCredit]) -> [AwardCredit] {
        let familyOrder = Dictionary(
            uniqueKeysWithValues: AwardFamily.allCases.enumerated().map { ($1, $0) }
        )
        let sorted = credits.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            let leftFamily = familyOrder[lhs.family] ?? 0
            let rightFamily = familyOrder[rhs.family] ?? 0
            if leftFamily != rightFamily { return leftFamily < rightFamily }
            return lhs.category < rhs.category
        }
        var seen: Set<String> = []
        return sorted.filter { seen.insert("\($0.family.rawValue)|\($0.category)").inserted }
    }
}

/// Prizes named on a person, not prizes named on a title they appeared in.
enum PersonAwardList {
    /// Newest ceremony first. A win drops the nomination for that same title, category, and year.
    static func awards(from credits: [AwardCredit], imdbID: String) -> [PersonAward] {
        let needle = imdbID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let matched = credits.filter { credit in
            guard !credit.title.isEmpty else { return false }
            return credit.recipients.contains { recipient in
                recipient.imdbID?.caseInsensitiveCompare(needle) == .orderedSame
            }
        }
        let wins = Set(matched.filter(\.won).map(suppressionKey))
        let visible = matched.filter { credit in
            credit.won || !wins.contains(suppressionKey(credit))
        }
        let familyOrder = Dictionary(
            uniqueKeysWithValues: AwardFamily.allCases.enumerated().map { ($1, $0) }
        )
        return visible.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            if lhs.won != rhs.won { return lhs.won }
            let leftFamily = familyOrder[lhs.family] ?? 0
            let rightFamily = familyOrder[rhs.family] ?? 0
            if leftFamily != rightFamily { return leftFamily < rightFamily }
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.key < rhs.key
        }
        .map { credit in
            PersonAward(
                key: credit.key,
                family: credit.family,
                category: credit.category,
                won: credit.won,
                year: credit.year,
                workTitle: credit.title,
                route: credit.work?.route(fallbackSeriesName: credit.title)
            )
        }
    }

    private static func suppressionKey(_ credit: AwardCredit) -> String {
        "\(credit.family.rawValue)|\(credit.category)|\(credit.year)|\(workIdentity(credit))"
    }

    private static func workIdentity(_ credit: AwardCredit) -> String {
        if let work = credit.work {
            switch work.kind {
            case .movie:
                return "m:\(work.movieID ?? -1)"
            case .series:
                return "s:\(work.seriesID ?? -1)"
            case .season:
                return "sn:\(work.seriesID ?? -1):\(work.seasonNumber ?? -1)"
            case .episode:
                return "ep:\(work.seriesID ?? -1):\(work.seasonNumber ?? -1):\(work.episodeNumber ?? -1)"
            }
        }
        if let imdbID = credit.imdbID { return "imdb:\(imdbID)" }
        return "title:\(credit.wikidataID ?? credit.title)"
    }
}

enum AwardJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO-8601 timestamp"
                )
            }
            return date
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        return encoder
    }

    static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

