//
//  DisplayDate.swift
//  TheSilverScreen
//
//  Calendar-day text for list and detail metadata. FormatStyle follows the
//  device locale without a shared DateFormatter.
//

import Foundation

enum DisplayDate {
    /// A TMDB calendar day, formatted for `locale` without shifting the day into another timezone.
    static func day(_ date: Date?, locale: Locale = .current) -> String {
        guard let date else { return "Date unavailable" }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        guard let stable = utc.date(from: parts) else { return "Date unavailable" }
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: utc, timeZone: utc.timeZone)
            .year()
            .month(.abbreviated)
            .day()
        return stable.formatted(style)
    }

    /// The calendar day a person rated a title or saved a note, in the device timezone.
    static func localDay(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
                .year()
                .month(.abbreviated)
                .day()
        )
    }

    /// Month/day/year for the rating label, short enough to stay on one line beside YOUR RATING.
    static func numericDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day, .year], from: date)
        return String(format: "%02d/%02d/%04d", parts.month ?? 1, parts.day ?? 1, parts.year ?? 1)
    }
}
