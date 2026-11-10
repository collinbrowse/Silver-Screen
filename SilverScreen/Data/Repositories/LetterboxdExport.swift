//
//  LetterboxdExport.swift
//  SilverScreen
//
//  Reads the CSV files in a Letterboxd data export (Settings → Import & Export →
//  Export Your Data) into one plan per film: its logged watches with dates, ratings,
//  rewatch marks and reviews, plus whether it is on the watchlist. No TMDB ids live
//  in the export, so films are keyed by name and year until `LetterboxdImporter`
//  matches them.
//

import Foundation

/// A film as Letterboxd names it. The match key for TMDB search.
struct LetterboxdFilm: Sendable, Hashable {
    let name: String
    /// Nil when the export left the year blank.
    let year: Int?
}

/// One logged watch from `diary.csv`, with its review joined from `reviews.csv`.
struct LetterboxdWatch: Sendable, Equatable {
    /// Nil for a film that is only in `watched.csv` or `ratings.csv`: watched, day unknown.
    let watchedOn: DiaryDay?
    /// Letterboxd stars, 0.5 to 5. Nil when unrated.
    let stars: Double?
    let isRewatch: Bool
    let review: String?
}

/// Everything the export says about one film.
struct LetterboxdFilmPlan: Sendable, Equatable {
    let film: LetterboxdFilm
    /// Diary watches oldest first; one undated watch when the film is watched or rated
    /// but never logged in the diary; empty for a watchlist-only film.
    var watches: [LetterboxdWatch]
    var onWatchlist: Bool
}

/// The files Letterboxd puts in its export ZIP that the import reads.
enum LetterboxdFile: String, CaseIterable, Sendable {
    case diary = "diary.csv"
    case reviews = "reviews.csv"
    case ratings = "ratings.csv"
    case watched = "watched.csv"
    case watchlist = "watchlist.csv"
}

enum LetterboxdExport {
    /// Builds one plan per film from the export's CSV text, keyed by file. Unknown or
    /// missing files are fine; a film only in `watchlist.csv` gets no watches. Plans
    /// come back in the order their films first appear.
    static func plans(from files: [LetterboxdFile: String]) -> [LetterboxdFilmPlan] {
        var order: [LetterboxdFilm] = []
        var plans: [LetterboxdFilm: LetterboxdFilmPlan] = [:]
        func plan(for film: LetterboxdFilm) -> LetterboxdFilmPlan {
            if let existing = plans[film] { return existing }
            order.append(film)
            return LetterboxdFilmPlan(film: film, watches: [], onWatchlist: false)
        }

        // Reviews attach to the diary row with the same entry URI, else the same film and day.
        // One with no diary row (Letterboxd allows undated reviews) is added after the diary.
        struct Review {
            let film: LetterboxdFilm
            let day: DiaryDay?
            let uri: String?
            let text: String
            let stars: Double?
            let isRewatch: Bool
            var key: String { LetterboxdExport.filmDayKey(film, day: day) }
        }
        let reviews: [Review] = records(files[.reviews]).compactMap { row in
            guard let film = row.film, let text = nonEmpty(row["Review"]) else { return nil }
            return Review(
                film: film,
                day: DiaryDay(iso: row["Watched Date"] ?? ""),
                uri: nonEmpty(row["Letterboxd URI"]),
                text: text,
                stars: stars(row["Rating"]),
                isRewatch: row["Rewatch"]?.lowercased() == "yes"
            )
        }
        var reviewByURI: [String: Int] = [:]
        var reviewByKey: [String: Int] = [:]
        for (index, review) in reviews.enumerated() {
            if let uri = review.uri { reviewByURI[uri] = index }
            reviewByKey[review.key] = index
        }
        var usedReviews = Set<Int>()

        for row in records(files[.diary]) {
            guard let film = row.film else { continue }
            let day = DiaryDay(iso: row["Watched Date"] ?? "") ?? DiaryDay(iso: row["Date"] ?? "")
            let reviewIndex = nonEmpty(row["Letterboxd URI"]).flatMap { reviewByURI[$0] }
                ?? reviewByKey[filmDayKey(film, day: day)]
            if let reviewIndex { usedReviews.insert(reviewIndex) }
            var entry = plan(for: film)
            entry.watches.append(
                LetterboxdWatch(
                    watchedOn: day,
                    stars: stars(row["Rating"]),
                    isRewatch: row["Rewatch"]?.lowercased() == "yes",
                    review: reviewIndex.map { reviews[$0].text }
                )
            )
            plans[film] = entry
        }

        for (index, review) in reviews.enumerated() where !usedReviews.contains(index) {
            var entry = plan(for: review.film)
            if let last = entry.watches.lastIndex(where: { $0.review == nil }) {
                let watch = entry.watches[last]
                entry.watches[last] = LetterboxdWatch(
                    watchedOn: watch.watchedOn,
                    stars: watch.stars ?? review.stars,
                    isRewatch: watch.isRewatch,
                    review: review.text
                )
            } else {
                entry.watches.append(
                    LetterboxdWatch(watchedOn: review.day, stars: review.stars, isRewatch: review.isRewatch, review: review.text)
                )
            }
            plans[review.film] = entry
        }

        // A rating with no rated diary watch rates the film's undated watch.
        for row in records(files[.ratings]) {
            guard let film = row.film, let rating = stars(row["Rating"]) else { continue }
            var entry = plan(for: film)
            if !entry.watches.contains(where: { $0.stars != nil }) {
                if entry.watches.isEmpty {
                    entry.watches.append(LetterboxdWatch(watchedOn: nil, stars: rating, isRewatch: false, review: nil))
                } else if let last = entry.watches.indices.last {
                    let watch = entry.watches[last]
                    entry.watches[last] = LetterboxdWatch(
                        watchedOn: watch.watchedOn,
                        stars: rating,
                        isRewatch: watch.isRewatch,
                        review: watch.review
                    )
                }
            }
            plans[film] = entry
        }

        for row in records(files[.watched]) {
            guard let film = row.film else { continue }
            var entry = plan(for: film)
            if entry.watches.isEmpty {
                entry.watches.append(LetterboxdWatch(watchedOn: nil, stars: nil, isRewatch: false, review: nil))
            }
            plans[film] = entry
        }

        for row in records(files[.watchlist]) {
            guard let film = row.film else { continue }
            var entry = plan(for: film)
            entry.onWatchlist = true
            plans[film] = entry
        }

        return order.compactMap { film in
            plans[film].map { plan in
                var sorted = plan
                sorted.watches.sort { ($0.watchedOn ?? .distantPast) < ($1.watchedOn ?? .distantPast) }
                return sorted
            }
        }
    }

    /// Which export file a picked file is, by name. Nil for anything else (likes, lists).
    static func file(named name: String) -> LetterboxdFile? {
        LetterboxdFile(rawValue: name.lowercased())
    }

    // MARK: - CSV

    /// One CSV row addressed by its header.
    struct Record {
        let fields: [String: String]
        subscript(column: String) -> String? { fields[column] }

        var film: LetterboxdFilm? {
            guard let name = LetterboxdExport.nonEmpty(fields["Name"]) else { return nil }
            return LetterboxdFilm(name: name, year: fields["Year"].flatMap { Int($0) })
        }
    }

    /// Rows of `text` keyed by its first line. Nil text gives no rows.
    static func records(_ text: String?) -> [Record] {
        guard let text else { return [] }
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces) }
        return rows.dropFirst().compactMap { row in
            guard row.contains(where: { !$0.isEmpty }) else { return nil }
            var fields: [String: String] = [:]
            for (index, column) in columns.enumerated() where index < row.count {
                fields[column] = row[index]
            }
            return Record(fields: fields)
        }
    }

    /// RFC 4180 CSV: quoted fields may hold commas, doubled quotes, and line breaks.
    /// Accepts LF or CRLF line ends and a leading byte-order mark.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var characters = text.unicodeScalars.makeIterator()
        var pending = characters.next()
        if pending == "\u{FEFF}" { pending = characters.next() }

        while let scalar = pending {
            pending = characters.next()
            if inQuotes {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.unicodeScalars.append("\"")
                        pending = characters.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r":
                    continue
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: - Helpers

    /// Letterboxd stars (0.5–5 in half steps). Nil for blank or out of range.
    private static func stars(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw.trimmingCharacters(in: .whitespaces)),
              value >= 0.5, value <= 5
        else {
            return nil
        }
        return value
    }

    fileprivate static func filmDayKey(_ film: LetterboxdFilm, day: DiaryDay?) -> String {
        "\(film.name)|\(film.year.map(String.init) ?? "")|\(day?.iso ?? "")"
    }

    fileprivate static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension DiaryDay {
    static let distantPast = DiaryDay(year: 1, month: 1, day: 1)
}

extension LetterboxdExport {
    /// Reads the export's CSV files from what the person picked: the files themselves, or
    /// the unzipped export folder. Files the import doesn't use, and any it can't read,
    /// are skipped, so an empty result means "no Letterboxd files here".
    static func read(urls: [URL], fileManager: FileManager = .default) -> [LetterboxdFile: String] {
        var files: [LetterboxdFile: String] = [:]
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let candidates = isDirectory
                ? (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                : [url]
            for candidate in candidates {
                guard let kind = file(named: candidate.lastPathComponent),
                      let text = try? String(contentsOf: candidate, encoding: .utf8)
                else { continue }
                files[kind] = text
            }
        }
        return files
    }
}
