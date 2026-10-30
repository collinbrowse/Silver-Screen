//
//  ListChangeNotice.swift
//  SilverScreen
//
//  Short confirmation after a title is added to or removed from a list.
//  Undo reverses that one change, including rows displaced onto Watchlist / In Progress.
//  TV watch toasts also restore the episode ledger captured in `TVWatchUndo`.
//  Adding to Watched or In Progress without a personal score also offers “Add rating,”
//  which opens the combined rating and note sheet. Callers can pass an explicit rating
//  key (e.g. episode) when the list row is the series.
//  Marking a movie watched with the eye also logs today's watch in the diary, and that
//  toast's Add rating opens the diary sheet on that same entry instead.
//

import Foundation

@Observable
@MainActor
final class ListChangeNotice {
    private(set) var message: String?
    /// When set, the banner shows an Add rating control for this annotation key.
    private(set) var ratingKey: AnnotationKey?
    /// Sheet opened from the banner’s Add rating control.
    private(set) var annotationEditor: AnnotationEditorSession?
    /// Diary sheet opened from a movie watch toast's Add rating, editing `loggedWatch`.
    private(set) var diaryEditor: DiaryEditorSession?
    /// Today's diary watch behind a movie watch toast. Add rating edits it rather than
    /// logging a second one.
    private(set) var loggedWatch: DiaryEntry?
    /// Bumps on every presentation so the banner refreshes even when copy is unchanged.
    private(set) var presentationID = 0
    /// Bumps after a successful Undo that may have restored TV watch progress — open
    /// season/series screens observe this and reload completed / Next up chrome.
    private(set) var watchRevision = 0
    /// True when membership Undo and/or a ledger restore is available.
    var canUndo: Bool { change != nil || watchUndo != nil }
    /// Whether the banner shows Add rating: a title without a score, or a movie watch
    /// just logged. Hidden while either sheet is up.
    var offersRating: Bool {
        (ratingKey != nil || loggedWatch != nil) && annotationEditor == nil && diaryEditor == nil
    }
    private var change: MembershipChange?
    private var lists: ListsRepository?
    private var tvWatch: TVWatchRepository?
    private var watchUndo: TVWatchUndo?
    private let annotations: AnnotationsRepository?
    private var generation = 0
    /// Title for the rating sheet (series/movie name from the list row when known).
    private var ratingTitle: String?
    /// Where a movie watch is logged. Nil in previews and tests that do not need it.
    private let diary: DiaryContext?
    /// Set only when this toast's watch created a new diary entry, so Undo removes that
    /// entry and never one that was already there.
    private var createdWatchID: UUID?

    init(annotations: AnnotationsRepository? = nil, diary: DiaryContext? = nil) {
        self.annotations = annotations
        self.diary = diary
    }

    /// The eye on a movie. Marking it watched also logs a diary watch dated today, with no
    /// rating, so the toast's Add rating can fill that watch in. A movie already logged
    /// today reuses that entry instead of adding a second. Un-marking leaves the diary
    /// alone. A diary failure is logged and the list change still shows.
    func showMovieWatch(_ change: MembershipChange, draft: ListItemDraft, using lists: ListsRepository) async {
        guard change.action == .added, draft.kind == .movie, let diary else {
            show(change, using: lists)
            return
        }
        let logged = await logTodaysWatch(of: draft, in: diary)
        show(change, using: lists)
        loggedWatch = logged?.entry
        createdWatchID = (logged?.isNew == true) ? logged?.entry.id : nil
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
            offerRating(
                for: ratingKey,
                message: fallbackMessage,
                using: lists,
                tvWatch: tvWatch,
                watchUndo: watchUndo
            )
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

    /// - Parameter ratingKey: When set, Add rating opens the editor for this key
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
        self.ratingTitle = nil
        self.annotationEditor = nil
        resetLoggedWatch()

        Task {
            let key = await Self.ratingKeyIfNeeded(
                for: change,
                preferred: preferredRatingKey,
                lists: lists,
                annotations: annotations
            )
            guard !Task.isCancelled, generation == token else { return }
            ratingKey = key
            if let key {
                ratingTitle = await Self.editorTitle(for: key, lists: lists)
            }
            let seconds: Double = key == nil && loggedWatch == nil ? 4 : 6
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    /// Rating prompt when membership did not change (series already on In Progress).
    /// Keeps `watchUndo` so an accidental episode mark can still restore the ledger.
    func offerRating(
        for ratingKey: AnnotationKey,
        message: String,
        using lists: ListsRepository,
        tvWatch: TVWatchRepository? = nil,
        watchUndo: TVWatchUndo? = nil
    ) {
        generation += 1
        let token = generation
        presentationID += 1
        self.change = nil
        self.lists = lists
        self.tvWatch = tvWatch
        self.watchUndo = watchUndo
        self.message = message
        self.ratingKey = nil
        self.ratingTitle = nil
        self.annotationEditor = nil
        resetLoggedWatch()

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
            if let key {
                ratingTitle = await Self.editorTitle(for: key, lists: lists)
            }
            let seconds: Double = key == nil && loggedWatch == nil ? 4 : 6
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    func undo() async {
        guard change != nil || watchUndo != nil else { return }
        let undoToken = watchUndo
        let watch = tvWatch
        let membership = change
        let listsRef = lists
        let createdWatch = createdWatchID
        clear()
        do {
            // Restore the episode ledger before list membership so In Progress captions stay valid.
            if let undoToken, let watch {
                try await watch.restore(undoToken)
            }
            if let membership, let listsRef {
                try await listsRef.undo(membership)
            }
            // The diary watch this toast logged goes with the Watched mark it came from.
            if let createdWatch, let diary {
                try await diary.diary.delete(id: createdWatch)
                diary.noteChange()
            }
            watchRevision += 1
        } catch is CancellationError {
            return
        } catch {
            // Partial undo — do not bump revision so open screens keep prior chrome.
            message = "Couldn’t undo. Try again."
            generation += 1
            let token = generation
            presentationID += 1
            Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, generation == token else { return }
                if self.message == "Couldn’t undo. Try again." {
                    clear()
                }
            }
        }
    }

    /// Opens the banner's rating sheet: the diary sheet on a movie watch this toast logged,
    /// otherwise the combined rating and note sheet for the banner's rating key.
    /// Cancels the auto-dismiss timer while the sheet is up.
    func openRatingEditor() async {
        guard annotationEditor == nil, diaryEditor == nil else { return }
        if let loggedWatch {
            generation += 1
            diaryEditor = .editing(loggedWatch)
            return
        }
        guard let ratingKey, let annotations else { return }
        generation += 1
        let record = try? await annotations.annotation(for: ratingKey)
        let title: String
        if let ratingTitle {
            title = ratingTitle
        } else if let resolved = await Self.editorTitle(for: ratingKey, lists: lists) {
            title = resolved
        } else {
            title = Self.fallbackEditorTitle(for: ratingKey)
        }
        annotationEditor = DetailAnnotationWriter.session(
            title: title,
            score: record?.score,
            note: record?.note
        )
    }

    /// Drops the toast-driven sheet without saving (Cancel / swipe away).
    /// Restarts the banner auto-dismiss clock so Undo/Add rating stay briefly available.
    func dismissRatingEditor() {
        guard annotationEditor != nil || diaryEditor != nil else { return }
        annotationEditor = nil
        diaryEditor = nil
        guard message != nil else { return }
        generation += 1
        let token = generation
        let seconds: Double = ratingKey == nil && loggedWatch == nil ? 3 : 6
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    /// Saves score and note from the toast sheet. Movies with a score stay on Watched.
    func saveRatingAnnotation(score: Double, note: String) async -> AnnotationEditorWriteResult {
        guard let ratingKey, let annotations else { return .failed }
        let (result, saved) = await DetailAnnotationWriter.save(
            score: score,
            note: note,
            for: ratingKey,
            annotations: annotations
        )
        switch result {
            case .succeeded:
                if ratingKey.kind == .movie, let lists {
                    await ensureMovieOnWatched(
                        subjectID: ratingKey.subjectID,
                        at: saved?.watchedAt,
                        lists: lists
                    )
                }
                annotationEditor = nil
                self.ratingKey = nil
                ratingTitle = nil
                // Keep Undo available briefly so a mistaken list add can still reverse.
                generation += 1
                let token = generation
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, generation == token else { return }
                    clear()
                }
            case .cancelled, .failed:
                break
        }
        return result
    }

    /// Clears rating and note from the toast sheet.
    func clearRatingAnnotation() async -> AnnotationEditorWriteResult {
        guard let ratingKey, let annotations else { return .failed }
        let result = await DetailAnnotationWriter.clear(for: ratingKey, annotations: annotations)
        switch result {
            case .succeeded:
                annotationEditor = nil
                self.ratingKey = nil
                ratingTitle = nil
                generation += 1
                let token = generation
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, generation == token else { return }
                    clear()
                }
            case .cancelled, .failed:
                break
        }
        return result
    }

    /// Saves the diary sheet opened from a movie watch toast: the same entry the eye
    /// logged, so the diary never gets a second row for one viewing. Undo stays briefly
    /// available afterward, as it does after a toast rating.
    func saveDiaryEntry(_ draft: DiaryEntryDraft) async -> AnnotationEditorWriteResult {
        guard let session = diaryEditor, let diary else { return .failed }
        do {
            loggedWatch = try await diary.save(session.entry(from: draft, now: Date()))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        diary.noteChange()
        finishDiaryEdit()
        return .succeeded
    }

    /// Deletes the toast's diary watch from its sheet. The Watched mark stays; this only
    /// removes the diary row, the same as deleting it from the diary.
    func deleteDiaryEntry() async -> AnnotationEditorWriteResult {
        guard let session = diaryEditor, let diary else { return .failed }
        do {
            try await diary.diary.delete(id: session.base.id)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        diary.noteChange()
        createdWatchID = nil
        finishDiaryEdit()
        return .succeeded
    }

    /// Closes the diary sheet and lets the toast run out with Undo still offered.
    private func finishDiaryEdit() {
        diaryEditor = nil
        loggedWatch = nil
        ratingKey = nil
        ratingTitle = nil
        generation += 1
        let token = generation
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    /// The movie's diary watch for today: an existing one when it was already logged
    /// today, otherwise a new unrated one. Nil when the diary cannot be read or written;
    /// the repository logs that, and the Watched mark still stands.
    private func logTodaysWatch(
        of draft: ListItemDraft,
        in diary: DiaryContext
    ) async -> (entry: DiaryEntry, isNew: Bool)? {
        let now = Date()
        let today = DiaryDay(now)
        let subject = DiarySubject.movie(draft.id)
        do {
            if let existing = try await diary.diary.entries(for: subject).first(where: { $0.watchedOn == today }) {
                return (existing, false)
            }
            let entry = DiaryEntry(
                id: UUID(),
                subject: subject,
                title: draft.title,
                releaseYear: DisplayDate.year(draft.releaseDate).flatMap(Int.init),
                posterPath: draft.imagePath,
                watchedOn: today,
                score: nil,
                review: nil,
                isRewatch: false,
                loggedAt: now
            )
            let saved = try await diary.diary.save(entry)
            diary.noteChange()
            return (saved, true)
        } catch {
            diary.logger.error("Movie watch was not logged in the diary", category: .persistence)
            return nil
        }
    }

    private func resetLoggedWatch() {
        loggedWatch = nil
        createdWatchID = nil
        diaryEditor = nil
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

    /// Drops the toast when the person leaves the screen it was about, e.g. by switching
    /// tabs, so Undo never shows next to unrelated content. A rating sheet opened from
    /// the toast keeps it until that sheet closes.
    func dismiss() {
        guard message != nil, annotationEditor == nil, diaryEditor == nil else { return }
        clear()
    }

    private func clear() {
        generation += 1
        message = nil
        ratingKey = nil
        ratingTitle = nil
        annotationEditor = nil
        resetLoggedWatch()
        change = nil
        lists = nil
        tvWatch = nil
        watchUndo = nil
    }

    /// Watched / In Progress adds without a score get a rating prompt. Removals and other lists do not.
    static func ratingKeyIfNeeded(
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

    /// Sheet title from the library row when the series/movie is listed.
    static func editorTitle(for key: AnnotationKey, lists: ListsRepository?) async -> String? {
        guard let lists else { return fallbackEditorTitle(for: key) }
        let itemKey: String
        switch key.kind {
            case .movie:
                itemKey = ListEntry.itemKey(id: key.subjectID, kind: .movie)
            case .tvSeries, .tvSeason, .tvEpisode:
                itemKey = ListEntry.itemKey(id: key.subjectID, kind: .tv)
        }
        do {
            let snapshot = try await lists.snapshot()
            let base = snapshot.entries.first(where: { $0.itemKey == itemKey })?.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (base?.isEmpty == false) ? base : nil
            switch key.kind {
                case .movie, .tvSeries:
                    return name ?? fallbackEditorTitle(for: key)
                case .tvSeason:
                    if let name {
                        return key.seasonNumber == 0
                            ? "\(name) · Specials"
                            : "\(name) · Season \(key.seasonNumber)"
                    }
                    return fallbackEditorTitle(for: key)
                case .tvEpisode:
                    if let name {
                        return "\(name) · S\(key.seasonNumber) · E\(key.episodeNumber)"
                    }
                    return fallbackEditorTitle(for: key)
            }
        } catch {
            return fallbackEditorTitle(for: key)
        }
    }

    static func fallbackEditorTitle(for key: AnnotationKey) -> String {
        switch key.kind {
            case .movie: return "Movie"
            case .tvSeries: return "Series"
            case .tvSeason:
                return key.seasonNumber == 0 ? "Specials" : "Season \(key.seasonNumber)"
            case .tvEpisode:
                return "S\(key.seasonNumber) · E\(key.episodeNumber)"
        }
    }
}
