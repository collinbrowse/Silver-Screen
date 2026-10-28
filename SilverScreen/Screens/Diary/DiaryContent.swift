//
//  DiaryContent.swift
//  SilverScreen
//
//  Display values for the diary list: entries and TV episode check-offs grouped by
//  month, newest first. Episodes of one show checked off on one day share a row.
//

import Foundation

/// One month header and its items, newest watch first.
struct DiaryMonth: Sendable, Equatable, Identifiable {
    /// `yyyy-MM`, stable across reloads.
    let id: String
    /// "October 2026"
    let title: String
    let items: [DiaryItem]

    /// The month's logged entries, without the episode rows.
    var rows: [DiaryRow] {
        items.compactMap { item -> DiaryRow? in
            guard case .entry(let row) = item else { return nil }
            return row
        }
    }
}

/// One line of the diary: a logged watch, or a show's episodes checked off that day.
enum DiaryItem: Sendable, Equatable, Identifiable {
    case entry(DiaryRow)
    case episodes(DiaryEpisodeGroup)

    var id: String {
        switch self {
            case .entry(let row): row.id.uuidString
            case .episodes(let row): row.id
        }
    }
}

/// Episodes of one show marked watched on one day. Read-only: it comes from TV progress,
/// so it is changed on the show's own screens, not in the diary.
struct DiaryEpisodeGroup: Sendable, Equatable, Identifiable {
    let seriesID: Int
    let seriesTitle: String
    let posterPath: String?
    let watchedOn: DiaryDay
    /// Sorted by season, then episode.
    let episodes: [TVEpisodeRef]
    /// Latest check-off in the group, which orders it against entries on the same day.
    let lastCompletedAt: Date
    let dayNumber: String
    let weekday: String
    /// "S2 · E3–E5", "S2 · 4 episodes", or "S1–S3 · 30 episodes".
    let episodesText: String
    let accessibilityLabel: String

    /// `episodes-<series>-<yyyy-MM-dd>`, stable across reloads.
    var id: String { "episodes-\(seriesID)-\(watchedOn.iso)" }
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
    /// Groups `entries` and `episodes` into months, newest month first and newest watch
    /// first inside each. Episodes of one show on one day become a single row.
    static func months(
        from entries: [DiaryEntry],
        episodes: [EpisodeWatch] = [],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DiaryMonth] {
        let entryItems = DiaryRepository.sorted(entries).map { entry in
            (day: entry.watchedOn, time: entry.loggedAt, item: DiaryItem.entry(row(for: entry, calendar: calendar, locale: locale)))
        }
        let episodeItems = episodeGroups(from: episodes, calendar: calendar, locale: locale).map { row in
            (day: row.watchedOn, time: row.lastCompletedAt, item: DiaryItem.episodes(row))
        }
        // Stable: entries keep the repository's order among themselves.
        let merged = (entryItems + episodeItems).enumerated().sorted { lhs, rhs in
            if lhs.element.day != rhs.element.day { return lhs.element.day > rhs.element.day }
            if lhs.element.time != rhs.element.time { return lhs.element.time > rhs.element.time }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var months: [DiaryMonth] = []
        var currentKey: String?
        var currentItems: [DiaryItem] = []
        var currentTitle = ""

        func flush() {
            if let currentKey, !currentItems.isEmpty {
                months.append(DiaryMonth(id: currentKey, title: currentTitle, items: currentItems))
            }
        }

        for element in merged {
            let key = String(format: "%04d-%02d", element.day.year, element.day.month)
            if key != currentKey {
                flush()
                currentKey = key
                currentItems = []
                currentTitle = monthTitle(element.day, calendar: calendar, locale: locale)
            }
            currentItems.append(element.item)
        }
        flush()
        return months
    }

    /// One row per show per day, newest day first.
    static func episodeGroups(
        from watches: [EpisodeWatch],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DiaryEpisodeGroup] {
        struct GroupKey: Hashable {
            let seriesID: Int
            let day: DiaryDay
        }
        let groups = Dictionary(grouping: watches) { watch in
            GroupKey(seriesID: watch.seriesID, day: DiaryDay(watch.completedAt, calendar: calendar))
        }
        let rows = groups.compactMap { key, watches -> DiaryEpisodeGroup? in
            guard let latest = watches.max(by: { $0.completedAt < $1.completedAt }) else { return nil }
            let episodes = Array(Set(watches.map(\.episode))).sorted()
            let date = key.day.date(in: calendar)
            let weekday = date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
            )
            let spokenDay = date.formatted(
                Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            )
            return DiaryEpisodeGroup(
                seriesID: key.seriesID,
                seriesTitle: latest.seriesTitle,
                posterPath: latest.posterPath,
                watchedOn: key.day,
                episodes: episodes,
                lastCompletedAt: latest.completedAt,
                dayNumber: String(key.day.day),
                weekday: weekday,
                episodesText: episodesText(episodes),
                accessibilityLabel: "\(latest.seriesTitle). \(spokenEpisodes(episodes)). Watched \(spokenDay)."
            )
        }
        return rows.sorted { lhs, rhs in
            if lhs.watchedOn != rhs.watchedOn { return lhs.watchedOn > rhs.watchedOn }
            if lhs.lastCompletedAt != rhs.lastCompletedAt { return lhs.lastCompletedAt > rhs.lastCompletedAt }
            return lhs.seriesID < rhs.seriesID
        }
    }

    /// "S2 · E3" for one episode, "S2 · E3–E5" for a run in one season, "S2 · 4 episodes"
    /// for a season with gaps, and "S1–S3 · 30 episodes" across seasons. `episodes` is sorted.
    static func episodesText(_ episodes: [TVEpisodeRef]) -> String {
        guard let first = episodes.first, let last = episodes.last else { return "" }
        if first.seasonNumber != last.seasonNumber {
            return "S\(first.seasonNumber)–S\(last.seasonNumber) · \(episodes.count) episodes"
        }
        if episodes.count == 1 {
            return "S\(first.seasonNumber) · E\(first.episodeNumber)"
        }
        if last.episodeNumber - first.episodeNumber == episodes.count - 1 {
            return "S\(first.seasonNumber) · E\(first.episodeNumber)–E\(last.episodeNumber)"
        }
        return "S\(first.seasonNumber) · \(episodes.count) episodes"
    }

    private static func spokenEpisodes(_ episodes: [TVEpisodeRef]) -> String {
        guard let first = episodes.first else { return "" }
        if episodes.count == 1 {
            return "Season \(first.seasonNumber), episode \(first.episodeNumber)"
        }
        return "\(episodes.count) episodes"
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
