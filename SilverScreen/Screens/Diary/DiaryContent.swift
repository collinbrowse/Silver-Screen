//
//  DiaryContent.swift
//  SilverScreen
//
//  Display values for the diary list: entries grouped by month, newest first.
//

import Foundation

/// One month header and its rows, newest watch first.
struct DiaryMonth: Sendable, Equatable, Identifiable {
    /// `yyyy-MM`, stable across reloads.
    let id: String
    /// "October 2026"
    let title: String
    let rows: [DiaryRow]
}

/// One entry, formatted for its row.
struct DiaryRow: Sendable, Equatable, Identifiable {
    let entry: DiaryEntry
    /// "16"
    let dayNumber: String
    /// "Thu"
    let weekday: String
    let yearText: String?
    /// "8.0"; nil when the watch is unrated.
    let ratingText: String?
    let reviewExcerpt: String?
    let tagsText: String?
    /// One sentence for VoiceOver, e.g. "Dune, 2021. Watched Thursday, October 16, 2026. Rated 8.0 out of 10. Rewatch."
    let accessibilityLabel: String

    var id: UUID { entry.id }
    var title: String { entry.title }
    var isRewatch: Bool { entry.isRewatch }
}

enum DiaryContent {
    /// Groups `entries` into months, newest month first and newest watch first inside each.
    static func months(
        from entries: [DiaryEntry],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DiaryMonth] {
        let sorted = DiaryRepository.sorted(entries)
        var months: [DiaryMonth] = []
        var currentKey: String?
        var currentRows: [DiaryRow] = []
        var currentTitle = ""

        func flush() {
            if let currentKey, !currentRows.isEmpty {
                months.append(DiaryMonth(id: currentKey, title: currentTitle, rows: currentRows))
            }
        }

        for entry in sorted {
            let key = String(format: "%04d-%02d", entry.watchedOn.year, entry.watchedOn.month)
            if key != currentKey {
                flush()
                currentKey = key
                currentRows = []
                currentTitle = monthTitle(entry.watchedOn, calendar: calendar, locale: locale)
            }
            currentRows.append(row(for: entry, calendar: calendar, locale: locale))
        }
        flush()
        return months
    }

    static func row(for entry: DiaryEntry, calendar: Calendar = .current, locale: Locale = .current) -> DiaryRow {
        let date = entry.watchedOn.date(in: calendar)
        let weekday = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
        )
        let spokenDay = date.formatted(
            Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
        let yearText = entry.releaseYear.map(String.init)
        let ratingText = entry.score.map { String(format: "%.1f", $0) }
        let tagsText = entry.tags.isEmpty ? nil : entry.tags.map { "#\($0)" }.joined(separator: " ")

        var spoken = [yearText.map { "\(entry.title), \($0)" } ?? entry.title]
        spoken.append("Watched \(spokenDay)")
        if let score = entry.score {
            spoken.append(String(format: "Rated %.1f out of 10", score))
        }
        if entry.isRewatch {
            spoken.append("Rewatch")
        }
        if entry.review != nil {
            spoken.append("Has a review")
        }
        if !entry.tags.isEmpty {
            spoken.append("Tags: \(entry.tags.joined(separator: ", "))")
        }

        return DiaryRow(
            entry: entry,
            dayNumber: String(entry.watchedOn.day),
            weekday: weekday,
            yearText: yearText,
            ratingText: ratingText,
            reviewExcerpt: entry.review,
            tagsText: tagsText,
            accessibilityLabel: spoken.joined(separator: ". ") + "."
        )
    }

    private static func monthTitle(_ day: DiaryDay, calendar: Calendar, locale: Locale) -> String {
        day.date(in: calendar).formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()
        )
    }
}
