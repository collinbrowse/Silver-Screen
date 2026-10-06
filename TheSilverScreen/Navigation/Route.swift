//
//  Route.swift
//  TheSilverScreen
//

import Foundation

/// Tabs on the bar. A stored `favorites` value still opens Library.
enum AppTab: Hashable, Sendable {
    case browse
    case library
    case search
}

extension AppTab: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        switch raw {
            case "favorites", "library":
                self = .library
            case "search":
                self = .search
            case "browse":
                self = .browse
            default:
                self = .browse
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .browse:
                try container.encode("browse")
            case .library:
                try container.encode("library")
            case .search:
                try container.encode("search")
        }
    }
}

enum Route: Hashable, Sendable, Codable {
    case movieDetail(id: Int)
    case person(id: Int)
    case personCredits(personID: Int, personName: String, department: CreditDepartment)
    case collection(id: Int)
    case tvSeries(id: Int)
    case tvSeason(seriesID: Int, seriesName: String, seasonNumber: Int, seriesSnapshot: SeriesListSnapshot)
    case tvEpisode(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        episodeNumber: Int,
        seriesSnapshot: SeriesListSnapshot
    )
    /// One library list. The id is the list's stable UUID.
    case libraryList(id: UUID)
    case awardFamily(AwardFamily)
    case awardTitles(AwardTitleRequest)
    case genreBrowse(MergedGenre)
}
