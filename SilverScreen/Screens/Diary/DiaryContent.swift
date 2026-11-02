//
//  DiaryContent.swift
//  SilverScreen
//
//  Display values for the diary list: entries grouped by month, newest first. Plain
//  first watches of one show's episodes on one day share a row; a rated, reviewed, or
//  rewatched episode keeps its own. Undated watches stay off the timeline.
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

/// One line of the diary: a logged watch, or a show's plain episode watches that day.
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

/// Plain first watches of one show's episodes on one day. Read-only here: rating one
/// happens on the episode's page, which then gives it its own row.
struct DiaryEpisodeGroup: Sendable, Equatable, Identifiable {
    let seriesID: Int
    let seriesTitle: String
    let posterPath: String?
    let watchedOn: DiaryDay
    /// Sorted by season, then episode.
    let episodes: [TVEpisodeRef]
    /// Latest log in the group, which orders it against entries on the same day.
    let lastCompletedAt: Date
    let dayNumber: String
    let weekday: String
    /// "S2 · E3–E5", "S2 · 4 episodes", or "S1–S3 · 30 episodes".
    let episodesText: String
    let accessibilityLabel: String
    /// A season rewatch logged in one go, kept apart from that day's first watches.
    var isRewatch = false

    /// `episodes-<series>-<yyyy-MM-dd>`, stable across reloads.
    var id: String { "episodes-\(seriesID)-\(watchedOn.iso)\(isRewatch ? "-rewatch" : "")" }
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
    /// "S2 · E3" for an episode entry; nil for a movie or series.
    let episodeText: String?
    /// One sentence for VoiceOver, e.g. "Dune, 2021. Watched Thursday, October 16, 2026. Rated 8.0 out of 10. Rewatch."
    let accessibilityLabel: String

    /// Shown with a Rewatch badge. See `DiaryContent.rewatchIDs(in:)`.
    let isRewatch: Bool

    var id: UUID { entry.id }
    var title: String { entry.title }
}

enum DiaryContent {
    /// Groups `entries` into months, newest month first and newest watch first inside
    /// each. With `groupsEpisodes`, plain episode watches of one show on one day become a
    /// single row; an episode's own history turns it off so each watch can be edited.
    static func months(
        from entries: [DiaryEntry],
        groupsEpisodes: Bool = true,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DiaryMonth] {
        let rewatches = rewatchIDs(in: entries)
        let dated = entries.filter(\.isDateKnown)
        let batched = seasonRewatchIDs(in: dated, rewatches: rewatches)
        let grouped = groupsEpisodes
            ? dated.filter { isPlainEpisodeWatch($0, rewatches: rewatches) || batched.contains($0.id) }
            : []
        let groupedIDs = Set(grouped.map(\.id))
        let entryItems = DiaryRepository.sorted(dated.filter { !groupedIDs.contains($0.id) }).map { entry in
            let entryRow = row(for: entry, isRewatch: rewatches.contains(entry.id), calendar: calendar, locale: locale)
            return (day: entry.watchedOn, time: entry.loggedAt, item: DiaryItem.entry(entryRow))
        }
        let episodeItems = episodeGroups(from: grouped, rewatches: batched, calendar: calendar, locale: locale).map { row in
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

    /// An episode's first watch with nothing of its own to show.
    private static func isPlainEpisodeWatch(_ entry: DiaryEntry, rewatches: Set<UUID>) -> Bool {
        entry.subject.episode != nil
            && entry.score == nil
            && entry.review == nil
            && !rewatches.contains(entry.id)
    }

    /// Plain rewatches of several episodes logged in one go, which is how a season rewatch
    /// is saved. They share a row; a lone episode's rewatch keeps its own.
    private static func seasonRewatchIDs(in entries: [DiaryEntry], rewatches: Set<UUID>) -> Set<UUID> {
        struct BatchKey: Hashable {
            let seriesID: Int
            let loggedAt: Date
        }
        let plainRewatches = entries.filter {
            $0.subject.episode != nil && $0.score == nil && $0.review == nil && rewatches.contains($0.id)
        }
        let batches = Dictionary(grouping: plainRewatches) {
            BatchKey(seriesID: $0.subject.tmdbID, loggedAt: $0.loggedAt)
        }
        return Set(batches.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    /// One row per show per day, newest day first. Entries in `rewatches` get a row of
    /// their own rather than sharing the day's first watches.
    static func episodeGroups(
        from watches: [DiaryEntry],
        rewatches: Set<UUID> = [],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DiaryEpisodeGroup] {
        struct GroupKey: Hashable {
            let seriesID: Int
            let day: DiaryDay
            let isRewatch: Bool
        }
        let groups = Dictionary(grouping: watches) { watch in
            GroupKey(seriesID: watch.subject.tmdbID, day: watch.watchedOn, isRewatch: rewatches.contains(watch.id))
        }
        let rows = groups.compactMap { key, watches -> DiaryEpisodeGroup? in
            guard let latest = watches.max(by: { $0.loggedAt < $1.loggedAt }) else { return nil }
            let episodes = Array(Set(watches.compactMap(\.subject.episode))).sorted()
            let date = key.day.date(in: calendar)
            let weekday = date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
            )
            let spokenDay = date.formatted(
                Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            )
            return DiaryEpisodeGroup(
                seriesID: key.seriesID,
                seriesTitle: latest.title,
                posterPath: latest.posterPath,
                watchedOn: key.day,
                episodes: episodes,
                lastCompletedAt: latest.loggedAt,
                dayNumber: String(key.day.day),
                weekday: weekday,
                episodesText: key.isRewatch ? "\(episodesText(episodes)) · Rewatch" : episodesText(episodes),
                accessibilityLabel: "\(latest.title). \(spokenEpisodes(episodes)). Watched \(spokenDay)."
                    + (key.isRewatch ? " Rewatch." : ""),
                isRewatch: key.isRewatch
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

    /// Undated watches for a title's "Earlier" section, latest logged first.
    static func earlierRows(
        from entries: [DiaryEntry],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DiaryRow] {
        let rewatches = rewatchIDs(in: entries)
        return DiaryRepository.sorted(entries.filter { !$0.isDateKnown }).map {
            row(for: $0, isRewatch: rewatches.contains($0.id), calendar: calendar, locale: locale)
        }
    }

    /// Entries that count as rewatches: every watch of a title after its earliest one,
    /// plus any entry stored as a rewatch (a Letterboxd import keeps its own flag, which
    /// covers a first log of something seen before the app). Nothing is switched by hand.
    static func rewatchIDs(in entries: [DiaryEntry]) -> Set<UUID> {
        let earliestFirst = DiaryRepository.sorted(entries).reversed()
        var seen = Set<DiarySubject>()
        var result = Set<UUID>()
        for entry in earliestFirst {
            if !seen.insert(entry.subject).inserted || entry.isRewatch {
                result.insert(entry.id)
            }
        }
        return result
    }

    static func row(
        for entry: DiaryEntry,
        isRewatch: Bool,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> DiaryRow {
        let date = entry.watchedOn.date(in: calendar)
        let weekday = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
        )
        let spokenDay = date.formatted(
            Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
        let yearText = entry.releaseYear.map(String.init)
        let ratingText = entry.score.map { String(format: "%.1f", $0) }
        let episodeText = entry.subject.episode.map { episodesText([$0]) }

        var spoken = [yearText.map { "\(entry.title), \($0)" } ?? entry.title]
        if let episode = entry.subject.episode {
            spoken.append("Season \(episode.seasonNumber), episode \(episode.episodeNumber)")
        }
        spoken.append(entry.isDateKnown ? "Watched \(spokenDay)" : "Watched, date unknown")
        if let score = entry.score {
            spoken.append(String(format: "Rated %.1f out of 10", score))
        }
        if isRewatch {
            spoken.append("Rewatch")
        }
        if entry.review != nil {
            spoken.append("Has a review")
        }

        return DiaryRow(
            entry: entry,
            dayNumber: entry.isDateKnown ? String(entry.watchedOn.day) : "–",
            weekday: entry.isDateKnown ? weekday : "",
            yearText: yearText,
            ratingText: ratingText,
            reviewExcerpt: entry.review,
            episodeText: episodeText,
            accessibilityLabel: spoken.joined(separator: ". ") + ".",
            isRewatch: isRewatch
        )
    }

    private static func monthTitle(_ day: DiaryDay, calendar: Calendar, locale: Locale) -> String {
        day.date(in: calendar).formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()
        )
    }
}
