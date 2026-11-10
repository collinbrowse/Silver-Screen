//
//  TMDBRating.swift
//  SilverScreen
//
//  Display strings for a TMDB user score. Movies and TV share one format.
//

import Foundation

enum TMDBRating {
    /// TMDB sends 0 when a title has no user score. That is not a rating.
    static func formatted(_ value: Double) -> String {
        guard value > 0 else { return String(localized: "Unavailable", comment: "TMDB score when a title has none") }
        return String(localized: "\(value, format: .number.precision(.fractionLength(1))) / 10")
    }

    static func accessibilityLabel(_ value: Double) -> String {
        guard value > 0 else { return String(localized: "TMDB rating unavailable") }
        return String(localized: "Rated \(value, format: .number.precision(.fractionLength(1))) out of 10")
    }
}
