//
//  WatchRepository.swift
//  SilverScreen
//
//  The one writer of "I watched this". A title is watched exactly when it has at least
//  one diary entry, so logging or removing a watch updates the diary and Watched as a
//  single operation, rolling back the first write if the second fails.
//

import Foundation

/// A watch the eye just logged, and the Watched change that came with it.
struct LoggedWatch: Sendable, Equatable {
    let entry: DiaryEntry
    let membership: MembershipChange
    /// What the watch adopted from the title's annotation, restored on Undo.
    var priorAnnotation: MediaAnnotation? = nil
}

/// Everything a removal took away, kept so Undo can put it back with the same ids.
struct RemovedWatches: Sendable, Equatable {
    let entries: [DiaryEntry]
    /// Nil when the title was not on Watched.
    let membership: MembershipChange?
}

actor WatchRepository {
    private let diary: DiaryRepository
    private let lists: ListsRepository
    /// The title ratings kept in step with the watches. Nil in tests that skip it.
    private let annotations: AnnotationsRepository?
    /// Takes an episode out of progress when its last watch goes. Nil in tests that skip it.
    private let tvWatch: TVWatchRepository?
    private let logger: any AppLogging
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        diary: DiaryRepository,
        lists: ListsRepository,
        annotations: AnnotationsRepository? = nil,
        tvWatch: TVWatchRepository? = nil,
        logger: any AppLogging,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.diary = diary
        self.lists = lists
        self.annotations = annotations
        self.tvWatch = tvWatch
        self.logger = logger
        self.now = now
        self.calendar = calendar
    }

    /// Watches of exactly this subject, newest first. A series subject leaves out its
    /// episodes' entries, unlike `DiaryRepository.entries(for:)`.
    func watches(of subject: DiarySubject) async throws -> [DiaryEntry] {
        try await diary.entries(for: subject).filter { $0.subject == subject }
    }

    /// Logs a watch of a movie dated today and puts it on Watched. `dateKnown` is false
    /// for onboarding's "seen it" picks, which were seen on no particular day.
    func logMovie(_ draft: ListItemDraft, dateKnown: Bool = true) async throws -> LoggedWatch {
        let date = now()
        let blank = DiaryEntry(
            id: UUID(),
            subject: .movie(draft.id),
            title: draft.title,
            releaseYear: DisplayDate.year(draft.releaseDate).flatMap(Int.init),
            posterPath: draft.imagePath,
            watchedOn: DiaryDay(date, calendar: calendar),
            score: nil,
            review: nil,
            isRewatch: false,
            loggedAt: date,
            isDateKnown: dateKnown
        )
        let adopted = try await annotations?.adopt(into: blank)
        let saved = try await diary.save(adopted?.entry ?? blank)
        do {
            let membership = try await lists.addToWatched(draft, at: date)
            return LoggedWatch(entry: saved, membership: membership, priorAnnotation: adopted?.prior)
        } catch {
            await rollBack("logged watch") { try await self.diary.delete(id: saved.id) }
            await restoreAnnotation(adopted?.prior, for: saved.subject)
            throw error
        }
    }

    /// Removes every watch of a movie and takes it off Watched.
    func removeMovie(_ draft: ListItemDraft) async throws -> RemovedWatches {
        let entries = try await watches(of: .movie(draft.id))
        try await diary.delete(ids: Set(entries.map(\.id)))
        do {
            let membership = try await removeFromWatched(itemKey: draft.itemKey)
            await syncTitleRating(for: .movie(draft.id))
            return RemovedWatches(entries: entries, membership: membership)
        } catch {
            await rollBack("removed watches") { try await self.diary.save(contentsOf: entries) }
            throw error
        }
    }

    /// Reverses `logMovie`: deletes the watch, including anything since added to it, and
    /// restores the lists as they were.
    func undo(_ logged: LoggedWatch) async throws {
        try await diary.delete(id: logged.entry.id)
        try await lists.undo(logged.membership)
        await syncTitleRating(for: logged.entry.subject)
        await restoreAnnotation(logged.priorAnnotation, for: logged.entry.subject)
    }

    /// Logs a rewatch of a whole season: one unrated watch per episode, sharing a log time
    /// so the diary shows them as one row. Nothing else changes, since every episode is
    /// already watched.
    func logSeasonRewatch(
        seriesID: Int,
        season: Int,
        episodes: [Int],
        title: String,
        posterPath: String?,
        on day: Date,
        dateKnown: Bool
    ) async throws -> [DiaryEntry] {
        let loggedAt = now()
        let entries = episodes.map { episode in
            DiaryEntry(
                id: UUID(),
                subject: .episode(seriesID: seriesID, season: season, episode: episode),
                title: title,
                releaseYear: nil,
                posterPath: posterPath,
                watchedOn: DiaryDay(day, calendar: calendar),
                score: nil,
                review: nil,
                isRewatch: false,
                loggedAt: loggedAt,
                isDateKnown: dateKnown
            )
        }
        return try await diary.save(contentsOf: entries)
    }

    /// Reverses `logSeasonRewatch`.
    func undo(seasonRewatch entries: [DiaryEntry]) async throws {
        try await diary.delete(ids: Set(entries.map(\.id)))
    }

    /// Puts back what `removed` took away. A tombstoned id is revived, so a restored
    /// watch keeps its identity.
    func restore(_ removed: RemovedWatches) async throws {
        try await diary.save(contentsOf: removed.entries)
        if let membership = removed.membership {
            try await lists.undo(membership)
        }
        if let subject = removed.entries.first?.subject {
            await syncTitleRating(for: subject)
        }
    }

    /// Sets the rating and review of a title's newest rated watch, or its newest watch.
    /// Onboarding uses this, because its picks have no Log sheet. No-op with no watch.
    func rate(_ subject: DiarySubject, score: Double?, review: String?) async throws {
        let entries = try await watches(of: subject)
        guard var watch = Self.ratedWatch(in: entries) ?? entries.first else { return }
        watch.score = score
        watch.review = review
        try await diary.save(watch)
        await syncTitleRating(for: subject)
    }

    /// Deletes one watch, as Watch History and the diary do. The title's last watch takes
    /// it off Watched too, since a title is watched exactly when it has a watch.
    func deleteWatch(_ entry: DiaryEntry) async throws {
        try await diary.delete(id: entry.id)
        if try await watches(of: entry.subject).isEmpty {
            if let episode = entry.subject.episode {
                try await tvWatch?.lastWatchDeleted(of: episode, seriesID: entry.subject.tmdbID)
            } else if entry.subject.kind == .movie {
                _ = try await removeFromWatched(itemKey: entry.subject.itemKey)
            }
        }
        await syncTitleRating(for: entry.subject)
    }

    /// Puts an annotation back as it was. Only called with a record that was adopted, so a
    /// failure costs that one note; it is logged, and the caller's outcome stands.
    private func restoreAnnotation(_ record: MediaAnnotation?, for subject: DiarySubject) async {
        guard let record, let annotations else { return }
        do {
            try await annotations.restore(record, for: subject.annotationKey)
        } catch {
            logger.error("Title annotation was not restored", category: .persistence)
        }
    }

    /// Points the title's rating at `ratedWatch`. If only this fails it is logged, and
    /// the watch change stands; the next write to the title repairs it.
    private func syncTitleRating(for subject: DiarySubject) async {
        guard let annotations else { return }
        do {
            let entries = try await watches(of: subject)
            try await annotations.syncRating(from: Self.ratedWatch(in: entries), for: subject)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Title rating was not updated after a watch change", category: .persistence)
        }
    }

    /// The watch whose score is the title's rating on detail pages and list rows, and
    /// the one the rating card names and opens. Nil when no watch has a score.
    /// `entries` are one subject's watches, newest first.
    nonisolated static func ratedWatch(in entries: [DiaryEntry]) -> DiaryEntry? {
        entries.first { $0.score != nil }
    }

    private func removeFromWatched(itemKey: String) async throws -> MembershipChange? {
        let snapshot = try await lists.snapshot()
        guard let watched = snapshot.list(.watched),
              snapshot.entries.contains(where: { $0.listID == watched.id && $0.itemKey == itemKey })
        else {
            return nil
        }
        return try await lists.remove(itemKey: itemKey, listID: watched.id)
    }

    /// Undoes the first half of a failed operation. The caller rethrows the original
    /// failure, so a rollback failure is only logged.
    private func rollBack(_ what: String, _ work: @Sendable () async throws -> some Sendable) async {
        do {
            _ = try await work()
        } catch {
            logger.error("Rollback of \(what) failed", category: .persistence)
        }
    }
}
