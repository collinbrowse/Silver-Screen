//
//  DiaryEntry.swift
//  SilverScreen
//
//  One logged watch of a movie or a whole series: the day it was watched, and the
//  rating, review, tags, and rewatch flag for that viewing. A title can have many
//  entries. Episode-by-episode history stays in TV progress (`completed_at`), so the
//  diary is not flooded with one row per episode. Columns line up with Letterboxd's
//  diary CSV; see PERSISTENCE.md.
//

import Foundation

/// A calendar day with no time or timezone, stored as `yyyy-MM-dd`.
/// A watch logged at 11 pm stays on that day when the device later changes timezone,
/// and Letterboxd's `Watched Date` column uses the same shape.
struct DiaryDay: Sendable, Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar` (the device calendar and timezone by default).
    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `yyyy-MM-dd`. Nil for any other shape or an impossible day.
    init?(iso raw: String) {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return nil
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: gregorian) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// `yyyy-MM-dd`, the stored and Letterboxd form.
    var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight of this day in `calendar`, for date pickers and formatting.
    func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    static func < (lhs: DiaryDay, rhs: DiaryDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The title a diary entry is about. People cannot be logged.
struct DiarySubject: Sendable, Hashable {
    let kind: ListItemKind
    let tmdbID: Int

    static func movie(_ id: Int) -> DiarySubject {
        DiarySubject(kind: .movie, tmdbID: id)
    }

    static func series(_ id: Int) -> DiarySubject {
        DiarySubject(kind: .tv, tmdbID: id)
    }

    /// Same key the lists use (`movie-550`), so a diary row can join to a list entry.
    var itemKey: String {
        ListEntry.itemKey(id: tmdbID, kind: kind)
    }
}

struct DiaryEntry: Sendable, Equatable, Hashable, Identifiable {
    let id: UUID
    let subject: DiarySubject
    /// Title when the watch was logged (Letterboxd `Name`).
    var title: String
    /// Release year when the watch was logged (Letterboxd `Year`). Importers match on it.
    var releaseYear: Int?
    var posterPath: String?
    /// Day of this viewing (Letterboxd `Watched Date`).
    var watchedOn: DiaryDay
    /// Half-point score from 0.5 through 10 for this viewing, or nil when unrated.
    /// The title's own rating (`MediaAnnotation`) is separate and is not changed by it.
    var score: Double?
    /// Review written for this viewing (Letterboxd `Review`, in reviews.csv).
    var review: String?
    var isRewatch: Bool
    var tags: [String]
    /// When the entry was logged (Letterboxd `Date`). An import keeps the original day,
    /// while the row's own `created_at` records when it reached this device.
    let loggedAt: Date

    init(
        id: UUID,
        subject: DiarySubject,
        title: String,
        releaseYear: Int?,
        posterPath: String?,
        watchedOn: DiaryDay,
        score: Double?,
        review: String?,
        isRewatch: Bool,
        tags: [String],
        loggedAt: Date
    ) {
        self.id = id
        self.subject = subject
        self.title = title
        self.releaseYear = releaseYear
        self.posterPath = posterPath
        self.watchedOn = watchedOn
        self.score = score
        self.review = review
        self.isRewatch = isRewatch
        self.tags = tags
        self.loggedAt = loggedAt
    }

    /// Drops an invalid score, a blank review, and blank or repeated tags (case-insensitive,
    /// first spelling wins), so the store never compares two spellings of "nothing".
    func normalized() -> DiaryEntry {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.score = score.flatMap { UserScore.isValid($0) ? $0 : nil }
        let trimmedReview = review?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.review = (trimmedReview?.isEmpty == false) ? trimmedReview : nil
        copy.tags = DiaryTags.normalized(tags)
        return copy
    }
}

/// Tag cleanup shared by the editor and the store.
enum DiaryTags {
    /// Trims each tag, drops empties, and keeps the first of any case-insensitive repeat.
    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// Splits comma-separated text, the way Letterboxd writes its `Tags` column.
    static func parse(_ text: String) -> [String] {
        normalized(text.components(separatedBy: ","))
    }

    /// Joins tags back into the editor and CSV form.
    static func joined(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }
}

/// Converts between this app's 0.5–10 score and Letterboxd's 0.5–5 star rating.
enum LetterboxdRating {
    /// Stars × 2. Every Letterboxd rating lands exactly on a valid score.
    static func score(fromStars stars: Double) -> Double? {
        let score = stars * 2
        return UserScore.isValid(score) ? score : nil
    }

    /// Score ÷ 2, rounded to the nearest half star (7.5 becomes 4 stars, 1 becomes 0.5).
    /// Lossy for odd half-points, because Letterboxd has half as many steps.
    static func stars(fromScore score: Double) -> Double? {
        guard UserScore.isValid(score) else { return nil }
        // One score point is one half star.
        let halfStars = score.rounded(.toNearestOrAwayFromZero)
        return max(halfStars, 1) / 2
    }
}
