//
//  SearchScope.swift
//  SilverScreen
//
//  View-all niche filter. Default is all types until the user taps a pill.
//

import Foundation

/// Single-select niche on the comprehensive search list. `.all` is the default.
enum SearchTypeNiche: String, CaseIterable, Sendable, Equatable {
    case all
    case movies
    case tv
    case people

    /// Pill labels for Movies / TV / People (`.all` has no pill).
    var title: String {
        switch self {
            case .all: String(localized: "All")
            case .movies: String(localized: "Movies")
            case .tv: String(localized: "TV")
            case .people: String(localized: "People")
        }
    }

    /// Niches the user can tap in the filter bar.
    static var pillCases: [SearchTypeNiche] { [.movies, .tv, .people] }
}
