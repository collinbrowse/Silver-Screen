//
//  PersonDetail.swift
//  TheSilverScreen
//

import Foundation

/// Cast vs crew credit list used by person detail carousels and View All.
enum CreditDepartment: String, Sendable, Hashable, Codable {
    case cast
    case crew
}

/// Movie or TV credit on a person.
enum CreditMediaType: String, Sendable, Hashable {
    case movie
    case tv
}

/// One cast or crew credit for a person, spanning movies and TV.
struct PersonCredit: Sendable, Identifiable, Equatable, Hashable {
    /// Stable identity across media types so movie 100 and TV 100 never collide.
    var id: String { "\(mediaType.rawValue)-\(mediaID)" }
    let mediaType: CreditMediaType
    let mediaID: Int
    let title: String
    let posterPath: String?
    let releaseDate: Date?
    let genreIDs: [Int]
    /// Character name (cast) or joined job titles (crew).
    let roleLabel: String
    /// TMDB popularity used to order credits (most notable first).
    let popularity: Double
    /// TMDB user score copied onto a list entry. Zero when the payload omitted it.
    let voteAverage: Double
}

/// Person detail returned by TMDB `person/{id}` with appended credits, images, and external ids.
struct PersonDetail: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let biography: String
    let birthday: Date?
    let deathday: Date?
    let placeOfBirth: String?
    let profilePath: String?
    let knownForDepartment: String?
    let imdbID: String?
    let images: [MovieImage]
    /// Cast credits sorted by popularity descending.
    let castCredits: [PersonCredit]
    /// Crew credits sorted by popularity descending (jobs merged per title).
    let crewCredits: [PersonCredit]
    /// TMDB popularity copied onto a people-list entry. Zero when the payload omitted it.
    let popularity: Double
}
