//
//  ListChangeNotice.swift
//  TheSilverScreen
//
//  Short confirmation after a title is added to or removed from a list.
//  Undo reverses that one change, including rows displaced onto Watchlist / In Progress.
//  TV watch toasts also restore the episode ledger captured in `TVWatchUndo`.
//  Adding to Watched or In Progress without a personal score also offers “Add rating.”
//  Callers can pass an explicit rating key (e.g. episode) when the list row is the series.
//

import Foundation

@Observable
@MainActor
final class ListChangeNotice {
    private(set) var message: String?
    /// When set, the banner shows an Add rating control for this annotation key.
    private(set) var ratingKey: AnnotationKey?
    /// Bumps on every presentation so the banner refreshes even when copy is unchanged.
    private(set) var presentationID = 0
    /// Bumps after a successful Undo that may have restored TV watch progress — open
    /// season/series screens observe this and reload completed / Next up chrome.
    private(set) var watchRevision = 0
    /// False for rating-only prompts (no membership change to reverse).
    var canUndo: Bool { change != nil }
    private var change: MembershipChange?
    private var lists: ListsRepository?
    private var tvWatch: TVWatchRepository?
    private var watchUndo: TVWatchUndo?
    private let annotations: AnnotationsRepository?
    private var generation = 0

    init(annotations: AnnotationsRepository? = nil) {
        self.annotations = annotations
    }

    /// Membership toast when the list actually changed; otherwise a watch confirmation
    /// with an optional Add rating CTA (series already on In Progress / Watched).
    func presentWatch(
        change: MembershipChange?,
        ratingKey: AnnotationKey,
        fallbackMessage: String,
        using lists: ListsRepository,
        tvWatch: TVWatchRepository? = nil,
        watchUndo: TVWatchUndo? = nil
    ) {
        if let change, change.confirmation != nil {
            show(
                change,
                using: lists,
                ratingKey: ratingKey,
                tvWatch: tvWatch,
                watchUndo: watchUndo
            )
        } else {
            offerRating(for: ratingKey, message: fallbackMessage, using: lists)
        }
    }

    /// Convenience for TV watch mutations that may toast membership and/or rating.
    func presentWatch(
        _ outcome: TVWatchOutcome,
        ratingKey: AnnotationKey,
        fallbackMessage: String,
        using lists: ListsRepository,
        tvWatch: TVWatchRepository
    ) {
        presentWatch(
            change: outcome.membershipChange,
            ratingKey: ratingKey,
            fallbackMessage: fallbackMessage,
            using: lists,
            tvWatch: tvWatch,
            watchUndo: outcome.watchUndo
        )
    }

    /// - Parameter ratingKey: When set, Add rating saves to this key (episode/season/series/movie)
    ///   instead of deriving one from the list `itemKey` (which for TV is always the series).
    func show(
        _ change: MembershipChange,
        using lists: ListsRepository,
        ratingKey preferredRatingKey: AnnotationKey? = nil,
        tvWatch: TVWatchRepository? = nil,
        watchUndo: TVWatchUndo? = nil
    ) {
        guard let message = change.confirmation else { return }
        generation += 1
        let token = generation
        presentationID += 1
        self.change = change
        self.lists = lists
        self.tvWatch = tvWatch
        self.watchUndo = watchUndo
        self.message = message
        self.ratingKey = nil

        Task {
            let key = await Self.ratingKeyIfNeeded(
                for: change,
                preferred: preferredRatingKey,
                lists: lists,
                annotations: annotations
            )
            guard !Task.isCancelled, generation == token else { return }
            ratingKey = key

            let seconds: Double = key == nil ? 4 : 6
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    /// Rating prompt with no list Undo — used when an episode is marked watched but
    /// membership did not change (series already on In Progress).
    func offerRating(
        for ratingKey: AnnotationKey,
        message: String,
        using lists: ListsRepository
    ) {
        generation += 1
        let token = generation
        presentationID += 1
        self.change = nil
        self.lists = lists
        self.tvWatch = nil
        self.watchUndo = nil
        self.message = message
        self.ratingKey = nil

        Task {
            let key: AnnotationKey?
            if let annotations,
               let score = try? await annotations.annotation(for: ratingKey)?.score,
               UserScore.isValid(score) {
                key = nil
            } else {
                key = ratingKey
            }
            guard !Task.isCancelled, generation == token else { return }
            self.ratingKey = key
            let seconds: Double = key == nil ? 4 : 6
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    func undo() async {
        guard let change, let lists else { return }
        let undoToken = watchUndo
        let watch = tvWatch
        clear()
        // Restore the episode ledger before list membership so In Progress captions stay valid.
        if let undoToken, let watch {
            try? await watch.restore(undoToken)
        }
        try? await lists.undo(change)
        watchRevision += 1
    }

    /// Saves a half-point score from the banner and dismisses the rating CTA.
    /// Movies with a score stay on Watched (rating counts as watched).
    func saveRating(_ score: Double) async {
        guard let ratingKey, let annotations else { return }
        do {
            let saved = try await annotations.saveScore(score, for: ratingKey)
            if ratingKey.kind == .movie, let lists {
                await ensureMovieOnWatched(subjectID: ratingKey.subjectID, at: saved.watchedAt, lists: lists)
            }
            self.ratingKey = nil
            // Keep Undo available briefly so a mistaken list add can still reverse.
            generation += 1
            let token = generation
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func ensureMovieOnWatched(subjectID: Int, at watchedAt: Date?, lists: ListsRepository) async {
        do {
            let snapshot = try await lists.snapshot()
            let itemKey = ListEntry.itemKey(id: subjectID, kind: .movie)
            let draft: ListItemDraft
            if let entry = snapshot.entries.first(where: { $0.itemKey == itemKey }) {
                draft = entry.listItem()
            } else {
                return
            }
            _ = try await lists.addToWatched(draft, at: watchedAt ?? Date())
        } catch {
            return
        }
    }

    private func clear() {
        message = nil
        ratingKey = nil
        change = nil
        lists = nil
        tvWatch = nil
        watchUndo = nil
    }

    /// Watched / In Progress adds without a score get a rating prompt. Removals and other lists do not.
    private static func ratingKeyIfNeeded(
        for change: MembershipChange,
        preferred: AnnotationKey?,
        lists: ListsRepository,
        annotations: AnnotationsRepository?
    ) async -> AnnotationKey? {
        guard change.action == .added, let annotations else { return nil }
        let key = preferred ?? annotationKey(forItemKey: change.itemKey)
        guard let key else { return nil }
        do {
            let snapshot = try await lists.snapshot()
            guard let list = snapshot.lists.first(where: { $0.id == change.listID }),
                  list.system == .watched || list.system == .inProgress else {
                return nil
            }
            if let score = try await annotations.annotation(for: key)?.score, UserScore.isValid(score) {
                return nil
            }
            return key
        } catch {
            return nil
        }
    }

    /// Maps a library `itemKey` (`movie-123` / `tv-456`) to a series or movie annotation.
    static func annotationKey(forItemKey itemKey: String) -> AnnotationKey? {
        let parts = itemKey.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let kind = ListItemKind(rawValue: parts[0]),
              let id = Int(parts[1]) else {
            return nil
        }
        switch kind {
            case .movie: return .movie(id)
            case .tv: return .series(id)
            case .person: return nil
        }
    }
}
