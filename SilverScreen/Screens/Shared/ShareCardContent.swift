//
//  ShareCardContent.swift
//  SilverScreen
//
//  What a share card says: one logged watch (rating, review, date) or one list
//  (name, count, first posters). Plain values, so the wording is tested without
//  rendering anything.
//

import Foundation

/// The text and poster paths a share card draws. Built from a diary entry or a list.
struct ShareCardContent: Sendable, Identifiable {
    enum Kind: Sendable, Equatable {
        /// One watch: big poster, rating, and review excerpt.
        case watch
        /// One list: a grid of up to `ShareCardContent.listPosterLimit` posters.
        case list
    }

    let id = UUID()
    let kind: Kind
    let title: String
    /// Under the title: the year for a watch, the title count for a list.
    let subtitle: String?
    /// "Watched March 3, 2026", "Rewatched …", or nil when the day isn't known.
    let dateLine: String?
    /// The score as shown in the app ("8.5"), or nil when unrated.
    let scoreText: String?
    /// The review, cut at a word boundary to fit the card.
    let reviewExcerpt: String?
    /// One poster for a watch; up to six for a list, in list order.
    let posterPaths: [String]

    static let listPosterLimit = 6
    static let reviewLimit = 280

    /// A card for one logged watch. `calendar` and `locale` format the watch date.
    static func watch(
        _ entry: DiaryEntry,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> ShareCardContent {
        var dateLine: String?
        if entry.isDateKnown {
            let date = entry.watchedOn.date(in: calendar)
            // Same timezone as the calendar that built the midnight, or the day can slip back one.
            let style = Date.FormatStyle(
                date: .long,
                time: .omitted,
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            let day = date.formatted(style)
            dateLine = entry.isRewatch
                ? String(localized: "Rewatched \(day)")
                : String(localized: "Watched \(day)")
        }
        return ShareCardContent(
            kind: .watch,
            title: entry.title,
            subtitle: entry.releaseYear.map(String.init),
            dateLine: dateLine,
            scoreText: entry.score.map { String(format: "%.1f", $0) },
            reviewExcerpt: excerpt(entry.review),
            posterPaths: entry.posterPath.map { [$0] } ?? []
        )
    }

    /// A card for a list: its name, how many titles it holds, and the first posters.
    static func list(_ list: LibraryList, entries: [ListEntry]) -> ShareCardContent {
        ShareCardContent(
            kind: .list,
            title: list.name,
            subtitle: entries.count == 1
                ? String(localized: "1 title")
                : String(localized: "\(entries.count) titles"),
            dateLine: nil,
            scoreText: nil,
            reviewExcerpt: nil,
            posterPaths: Array(entries.compactMap(\.imagePath).prefix(listPosterLimit))
        )
    }

    /// Trims whitespace and cuts past `reviewLimit` characters at the last word break,
    /// adding an ellipsis. Nil for an empty review.
    static func excerpt(_ review: String?) -> String? {
        guard let trimmed = review?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.count > reviewLimit else { return trimmed }
        let head = trimmed.prefix(reviewLimit)
        let cut = head.lastIndex(where: \.isWhitespace) ?? head.endIndex
        return head[..<cut].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
