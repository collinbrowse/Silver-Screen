//
//  TMDBLocale.swift
//  TheSilverScreen
//
//  Language and region query items from the device locale. Region is omitted
//  when the locale has none, so a language-only device does not send an empty region.
//

import Foundation

enum TMDBLocale {
    /// BCP-47 tag TMDB accepts, such as `en-US`. A locale with no region is just the language (`en`).
    static func languageTag(for locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        if let region = regionCode(for: locale) {
            return "\(language)-\(region)"
        }
        return language
    }

    /// ISO language plus `null`, so posters with no language tag still load.
    static func imageLanguages(for locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        return "\(language),null"
    }
    /// ISO region, or nil when the device locale does not have one.
    static func regionCode(for locale: Locale) -> String? {
        guard let code = locale.region?.identifier, !code.isEmpty else { return nil }
        return code
    }

    static func queryItems(locale: Locale, page: Int, extra: [URLQueryItem] = []) -> [URLQueryItem] {
        var items = extra
        items.append(URLQueryItem(name: "language", value: languageTag(for: locale)))
        if let region = regionCode(for: locale) {
            items.append(URLQueryItem(name: "region", value: region))
        }
        items.append(URLQueryItem(name: "page", value: String(page)))
        return items
    }
}

/// Calendar-day strings (`yyyy-MM-dd`) in a timezone. Upcoming TV uses the user's zone
/// so "tomorrow" matches the day on their phone.
enum TMDBDay {
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func adding(days: Int, to date: Date, timeZone: TimeZone = .current) -> Date {
        let calendar = calendar(timeZone)
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
