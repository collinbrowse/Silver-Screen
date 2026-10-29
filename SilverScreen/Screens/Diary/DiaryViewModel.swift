//
//  DiaryViewModel.swift
//  SilverScreen
//

import Foundation

/// The diary list: every logged watch and every TV episode check-off, grouped by month,
/// newest first, with edit and delete for logged watches. A failed reload or delete keeps
/// the list on screen with a failed activity. Episode history that cannot be read is
/// logged and left out, so the logged watches still show.
///
/// With a `scope` it is one title's watch history instead, reached from that title's page.
@Observable
@MainActor
final class DiaryViewModel {
    private(set) var state: LoadState<[DiaryMonth]> = .idle
    /// Open editor for an existing entry, or nil.
    var editor: DiaryEditorSession?

    /// Nil for the whole diary.
    let scope: DiaryScope?
    private let context: DiaryContext
    private let calendar: Calendar
    private let locale: Locale
    private let now: @Sendable () -> Date

    init(
        context: DiaryContext,
        scope: DiaryScope? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.scope = scope
        self.calendar = calendar
        self.locale = locale
        self.now = now
    }

    /// Moves whenever any screen writes the diary; the view reloads on change.
    var contextRevision: Int { context.revision }

    var navigationTitle: String { scope?.title ?? "Diary" }

    /// Rows link back to their title only in the full diary; a title's history was
    /// opened from that title.
    var showsTitleLinks: Bool { scope == nil }

    /// Rows show their poster and title only in the full diary; on one title's history
    /// the screen's name already says which title every row is.
    var showsRowTitles: Bool { scope == nil }

    /// A title's name can be long, so its history uses the smaller inline title instead
    /// of a large one that truncates.
    var prefersInlineTitle: Bool { scope != nil }

    func load() async {
        switch state {
            case .loaded(let months, _):
                state = .loaded(months, activity: .refreshing)
            case .empty:
                break
            default:
                state = .loading
        }
        do {
            let entries: [DiaryEntry]
            if let subject = scope?.subject {
                entries = try await context.diary.entries(for: subject)
            } else {
                entries = try await context.diary.entries()
            }
            let episodes = try await episodeWatches()
            let months = DiaryContent.months(from: entries, episodes: episodes, calendar: calendar, locale: locale)
            state = months.isEmpty ? .empty : .loaded(months)
        } catch is CancellationError {
            return
        } catch let error as AppError {
            fail(with: error)
        } catch {
            fail(with: .unknown)
        }
    }

    func edit(_ row: DiaryRow) {
        editor = .editing(row.entry, calendar: calendar)
    }

    func dismissEditor() {
        editor = nil
    }

    /// Saves the open editor's draft. Success closes the sheet; failure keeps it open.
    func save(_ draft: DiaryEntryDraft) async -> AnnotationEditorWriteResult {
        guard let session = editor else { return .cancelled }
        do {
            try await context.diary.save(session.entry(from: draft, now: now(), calendar: calendar))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        editor = nil
        context.noteChange()
        await load()
        return .succeeded
    }

    /// Deletes the entry open in the editor. Failure keeps the sheet open.
    func deleteEditorEntry() async -> AnnotationEditorWriteResult {
        guard let session = editor, !session.isNew else { return .cancelled }
        do {
            try await context.diary.delete(id: session.base.id)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        editor = nil
        context.noteChange()
        await load()
        return .succeeded
    }

    /// Deletes from a swipe or context menu. Failure leaves the list with a failed activity.
    func delete(_ row: DiaryRow) async {
        do {
            try await context.diary.delete(id: row.id)
        } catch is CancellationError {
            return
        } catch {
            if case .loaded(let months, _) = state {
                state = .loaded(months, activity: .failed(.persistence))
            }
            return
        }
        context.noteChange()
        await load()
    }

    /// The show an episodes row belongs to.
    func route(for row: DiaryEpisodeGroup) -> Route {
        .tvSeries(id: row.seriesID)
    }

    /// The detail screen for the row's title.
    func route(for row: DiaryRow) -> Route {
        switch row.entry.subject.kind {
            case .tv: .tvSeries(id: row.entry.subject.tmdbID)
            case .movie, .person: .movieDetail(id: row.entry.subject.tmdbID)
        }
    }

    /// Episode history, or none when it cannot be read (the repository logs the failure).
    /// Only cancellation propagates.
    private func episodeWatches() async throws -> [EpisodeWatch] {
        do {
            guard let subject = scope?.subject else {
                return try await context.diary.episodeWatches()
            }
            guard subject.kind == .tv else { return [] }
            return try await context.diary.episodeWatches(seriesID: subject.tmdbID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    private func fail(with error: AppError) {
        if case .loaded(let months, _) = state {
            state = .loaded(months, activity: .failed(error))
        } else {
            state = .failed(error)
        }
    }
}
