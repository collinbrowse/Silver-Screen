//
//  SearchListing.swift
//  TheSilverScreen
//

import Foundation

enum SearchListing: Sendable, Equatable {
    case movies([CatalogMovieRow])
    case tv([CatalogTVRow])
    case people([CatalogPersonRow])

    var isEmpty: Bool {
        switch self {
            case .movies(let rows): rows.isEmpty
            case .tv(let rows): rows.isEmpty
            case .people(let rows): rows.isEmpty
        }
    }

    func applying(_ scores: [AnnotationKey: SavedUserScore]) -> SearchListing {
        switch self {
            case .movies(let rows):
                .movies(rows.map { $0.withUserScore(scores[.movie($0.id)]) })
            case .tv(let rows):
                .tv(rows.map { $0.withUserScore(scores[.series($0.id)]) })
            case .people:
                self
        }
    }
}
