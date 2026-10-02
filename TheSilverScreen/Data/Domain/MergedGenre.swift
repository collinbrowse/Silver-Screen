//
//  MergedGenre.swift
//  TheSilverScreen
//
//  Movie and TV genre ids merged into one Search shelf card. TMDB uses
//  different names and ids on each side; Discover filters with OR within a side.
//

import Foundation

/// Search shelf genres, alphabetical by display name.
enum MergedGenre: String, CaseIterable, Codable, Hashable, Sendable {
    case actionAndAdventure
    case animation
    case comedy
    case crime
    case documentary
    case drama
    case family
    case mystery
    case sciFiAndFantasy
    case warAndPolitics
    case western

    var title: String {
        switch self {
            case .actionAndAdventure: "Action & Adventure"
            case .animation: "Animation"
            case .comedy: "Comedy"
            case .crime: "Crime"
            case .documentary: "Documentary"
            case .drama: "Drama"
            case .family: "Family"
            case .mystery: "Mystery"
            case .sciFiAndFantasy: "Sci-Fi & Fantasy"
            case .warAndPolitics: "War & Politics"
            case .western: "Western"
        }
    }

    var movieGenreIDs: [Int] {
        switch self {
            case .actionAndAdventure: [28, 12]
            case .animation: [16]
            case .comedy: [35]
            case .crime: [80]
            case .documentary: [99]
            case .drama: [18]
            case .family: [10751]
            case .mystery: [9648]
            case .sciFiAndFantasy: [878, 14]
            case .warAndPolitics: [10752]
            case .western: [37]
        }
    }

    var tvGenreIDs: [Int] {
        switch self {
            case .actionAndAdventure: [10759]
            case .animation: [16]
            case .comedy: [35]
            case .crime: [80]
            case .documentary: [99]
            case .drama: [18]
            case .family: [10751, 10762]
            case .mystery: [9648]
            case .sciFiAndFantasy: [10765]
            case .warAndPolitics: [10768]
            case .western: [37]
        }
    }

    /// Cards on the Search home shelf, sorted A–Z by title.
    static var searchShelf: [MergedGenre] {
        allCases.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
}
