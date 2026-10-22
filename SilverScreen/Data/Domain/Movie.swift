//
//  Movie.swift
//  SilverScreen
//

import Foundation

struct Movie: Sendable, Identifiable, Hashable {
    let id: Int
    let title: String
    let posterPath: String?
    let releaseDate: Date?
    let voteAverage: Double
    let genreIDs: [Int]
    /// TMDB popularity. Zero when the payload did not include it.
    var popularity: Double = 0
    /// How many TMDB users rated it. Zero when the payload did not include it.
    var voteCount: Int = 0
}
