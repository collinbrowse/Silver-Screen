//
//  TourStop.swift
//  SilverScreen
//
//  The feature tour that follows onboarding: which stops it makes, what each
//  one says, and which on-screen views it highlights.
//

import Foundation

/// A view the tour can cut out of the dim layer. Views mark themselves with `.tourAnchor`.
enum TourAnchor: String, Hashable, Sendable {
    case libraryWatched
    case libraryInProgress
    case libraryWatchlist
    case newList
    case browseEye
    case awardShelves
    case ratingCard
    case seasons

    /// Scroll target id for screens that bring the anchor into view.
    var scrollID: String { "tour.\(rawValue)" }
}

/// One stop on the tour. Detail stops carry the library title they open.
enum TourStop: Hashable, Sendable {
    case libraryLists
    case newList
    case eyeButton
    case awards
    case rateMovie(id: Int, title: String)
    case trackSeries(id: Int, title: String)

    /// Highlighted together; the cutout covers all of them that are on screen.
    var anchors: [TourAnchor] {
        switch self {
            case .libraryLists: [.libraryWatched, .libraryInProgress, .libraryWatchlist]
            case .newList: [.newList]
            case .eyeButton: [.browseEye]
            case .awards: [.awardShelves]
            case .rateMovie: [.ratingCard]
            case .trackSeries: [.seasons]
        }
    }

    /// Anchor a scrolling detail screen should bring to the middle, if any.
    var scrollAnchor: TourAnchor? {
        switch self {
            case .rateMovie: .ratingCard
            case .trackSeries: .seasons
            case .libraryLists, .newList, .eyeButton, .awards: nil
        }
    }

    var title: String {
        switch self {
            case .libraryLists: String(localized: "Your library")
            case .newList: String(localized: "Make your own lists")
            case .eyeButton: String(localized: "Mark it watched")
            case .awards: String(localized: "Award winners")
            case .rateMovie: String(localized: "Rate it anytime")
            case .trackSeries: String(localized: "Track episodes")
        }
    }

    var message: String {
        switch self {
            case .libraryLists:
                String(localized: "What you've seen is on Watched, and your picks are on Watchlist. Shows you're partway through move to In Progress.")
            case .newList:
                String(localized: "Tap + to start a list of your own, like Date Night or Halloween.")
            case .eyeButton:
                String(localized: "Tap the eye on any title to put it on Watched. For a show, it marks every episode.")
            case .awards:
                String(localized: "Browse every Oscar, BAFTA, and Emmy winner and nominee, by category.")
            case .rateMovie:
                String(localized: "Tap your rating to change it or add a review. A rewatch gets a rating of its own, and you can rate whole shows and single seasons too.")
            case .trackSeries(_, let title):
                String(localized: "Open a season of \(title) to check off episodes. Next up keeps your place.")
        }
    }

    /// The stops for this library. Detail stops need a movie or series on Watched to open.
    static func plan(for snapshot: LibrarySnapshot) -> [TourStop] {
        var stops: [TourStop] = [.libraryLists, .newList, .eyeButton, .awards]
        guard let watched = snapshot.list(.watched) else { return stops }
        let entries = snapshot.entries.filter { $0.listID == watched.id }
        if let movie = entries.first(where: { $0.kind == .movie }) {
            stops.append(.rateMovie(id: movie.itemID, title: movie.title))
        }
        if let series = entries.first(where: { $0.kind == .tv }) {
            stops.append(.trackSeries(id: series.itemID, title: series.title))
        }
        return stops
    }
}
