//
//  DiaryEntryDraft.swift
//  SilverScreen
//
//  The editor sheet's payload: what it starts with, what it hands back, and how the
//  result becomes a stored entry.
//

import Foundation

/// Editable fields of one watch, as the sheet shows them. Rewatch is not one of them:
/// the diary works it out from the title's history (`DiaryContent.rewatchIDs(in:)`).
struct DiaryEntryDraft: Sendable, Equatable {
    var watchedOn: Date
    var score: Double?
    var review: String
}

/// One presentation of the editor, for a new watch or an existing entry.
struct DiaryEditorSession: Sendable, Equatable, Identifiable {
    let id: UUID
    /// Movie or series name shown as the sheet title.
    let title: String
    /// The entry being edited, or a template carrying the title's identity for a new one.
    let base: DiaryEntry
    let isNew: Bool
    let draft: DiaryEntryDraft

    var canDelete: Bool { !isNew }

    /// Opens an existing entry with its saved values.
    static func editing(_ entry: DiaryEntry, calendar: Calendar = .current) -> DiaryEditorSession {
        DiaryEditorSession(
            id: UUID(),
            title: entry.title,
            base: entry,
            isNew: false,
            draft: DiaryEntryDraft(
                watchedOn: entry.watchedOn.date(in: calendar),
                score: entry.score,
                review: entry.review ?? ""
            )
        )
    }

    /// Opens a new watch of `title` dated today. The current title rating is prefilled
    /// so a person who already rated it only picks a date.
    static func logging(
        _ title: LogWatchTitle,
        currentScore: Double?,
        now: Date
    ) -> DiaryEditorSession {
        let base = DiaryEntry(
            id: UUID(),
            subject: title.subject,
            title: title.title,
            releaseYear: title.releaseYear,
            posterPath: title.posterPath,
            watchedOn: DiaryDay(now),
            score: nil,
            review: nil,
            isRewatch: false,
            loggedAt: now
        )
        return DiaryEditorSession(
            id: UUID(),
            title: title.title,
            base: base,
            isNew: true,
            draft: DiaryEntryDraft(
                watchedOn: now,
                score: currentScore.flatMap { UserScore.isValid($0) ? $0 : nil },
                review: ""
            )
        )
    }

    /// The entry to store for `draft`. A new entry is stamped as logged at `now`;
    /// an edited one keeps its original log time.
    func entry(from draft: DiaryEntryDraft, now: Date, calendar: Calendar = .current) -> DiaryEntry {
        DiaryEntry(
            id: base.id,
            subject: base.subject,
            title: base.title,
            releaseYear: base.releaseYear,
            posterPath: base.posterPath,
            watchedOn: DiaryDay(draft.watchedOn, calendar: calendar),
            score: draft.score,
            review: draft.review,
            // An imported rewatch flag survives an edit; a new log stores none.
            isRewatch: base.isRewatch,
            loggedAt: isNew ? now : base.loggedAt
        ).normalized()
    }
}

/// The title a new diary watch is logged for (a rewatch from a movie's history).
struct LogWatchTitle: Sendable, Equatable {
    let subject: DiarySubject
    let title: String
    let releaseYear: Int?
    let posterPath: String?
    /// Snapshot used to put the title on Watched when a watch is logged.
    let listItem: ListItemDraft

    init(subject: DiarySubject, title: String, releaseYear: Int?, posterPath: String?, listItem: ListItemDraft) {
        self.subject = subject
        self.title = title
        self.releaseYear = releaseYear
        self.posterPath = posterPath
        self.listItem = listItem
    }

    init(series: TVSeriesDetail) {
        subject = .series(series.id)
        title = series.name
        releaseYear = DisplayDate.year(series.firstAirDate).flatMap(Int.init)
        posterPath = series.posterPath
        listItem = series.listItem()
    }

    init(movie: MovieDetail) {
        subject = .movie(movie.id)
        title = movie.title
        releaseYear = DisplayDate.year(movie.releaseDate).flatMap(Int.init)
        posterPath = movie.posterPath
        listItem = movie.listItem()
    }
}
