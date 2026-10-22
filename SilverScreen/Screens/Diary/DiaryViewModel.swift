//
//  DiaryViewModel.swift
//  SilverScreen
//

import Foundation

/// The diary list: every logged watch grouped by month, newest first, with edit and delete.
/// A failed reload or delete keeps the list on screen with a failed activity.
@Observable
@MainActor
final class DiaryViewModel {
    private(set) var state: LoadState<[DiaryMonth]> = .idle
    /// Open editor for an existing entry, or nil.
    var editor: DiaryEditorSession?

    private let context: DiaryContext
    private let calendar: Calendar
    private let locale: Locale
    private let now: @Sendable () -> Date

    init(
        context: DiaryContext,
        calendar: Calendar = .current,
        locale: Locale = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.calendar = calendar
        self.locale = locale
        self.now = now
    }

    /// Moves whenever any screen writes the diary; the view reloads on change.
    var contextRevision: Int { context.revision }

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
            let entries = try await context.diary.entries()
            let months = DiaryContent.months(from: entries, calendar: calendar, locale: locale)
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

    /// The detail screen for the row's title.
    func route(for row: DiaryRow) -> Route {
        switch row.entry.subject.kind {
            case .tv: .tvSeries(id: row.entry.subject.tmdbID)
            case .movie, .person: .movieDetail(id: row.entry.subject.tmdbID)
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
