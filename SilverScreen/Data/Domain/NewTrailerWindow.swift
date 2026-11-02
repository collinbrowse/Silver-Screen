//
//  NewTrailerWindow.swift
//  SilverScreen
//
//  What "released this week" means for the New Trailers Browse window.
//

import Foundation

/// Decides whether a trailer's YouTube publish time counts as new.
enum NewTrailerWindow {
    /// True when `publishedAt` falls inside the New Trailers window that ends at `today`.
    /// `timeZone` is the user's, so day boundaries match their calendar, not UTC.
    static func contains(_ publishedAt: Date, today: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startOfToday = calendar.startOfDay(for: today)
        guard let startDate = calendar.date(byAdding: .day, value: -6, to: startOfToday) else {
            return false
        }
        return publishedAt >= startDate
    }
}
