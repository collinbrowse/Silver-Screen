//
//  TMDBRating.swift
//  TheSilverScreen
//
//  Display strings for a TMDB user score. Movies and TV share one format.
//

import Foundation

enum TMDBRating {
    /// TMDB sends 0 when a title has no user score. That is not a rating.
    static func formatted(_ value: Double) -> String {
        guard value > 0 else { return "Unavailable" }
        return String(format: "%.1f / 10", value)
    }

    static func accessibilityLabel(_ value: Double) -> String {
        guard value > 0 else { return "TMDB rating unavailable" }
        return String(format: "Rated %.1f out of 10", value)
    }
}
