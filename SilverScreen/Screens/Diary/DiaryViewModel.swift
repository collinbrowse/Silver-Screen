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
/// A movie's history is also where a rewatch is logged (`beginRewatch()`).
@Observable
@MainActor
final class DiaryViewModel {
    private(set) var state: LoadState<[DiaryMonth]> = .idle
    /// Open editor for an existing entry or a new rewatch, or nil.
    var editor: DiaryEditorSession?

    /// Undated watches, shown under "Earlier" on a title's history. Always empty on the
    /// full diary, because they belong to no day on its timeline.
    private(set) var earlierRows: [DiaryRow] = []
    /// Poster path by season number, on a show's history.
    private(set) var seasonPosters: [Int: String] = [:]

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

    /// Log a Rewatch shows on a movie's or episode's own history. A show is rewatched
    /// through its episodes, so its history has no button.
    var canLogRewatch: Bool {
        guard let subject = scope?.subject else { return false }
        return !subject.isWholeSeries
    }

    /// A show's history leads each row with its season's poster, since the rows of one
    /// show would otherwise look the same.
    var showsSeasonPosters: Bool { scope?.subject.kind == .tv }

    /// The poster leading an entry on a show's history: its episode's season, or the
    /// series poster for a whole-series entry or a season with none.
    func historyPoster(for row: DiaryRow) -> String? {
        row.entry.subject.episode.flatMap { seasonPosters[$0.seasonNumber] } ?? row.entry.posterPath
    }

    /// The poster leading an episodes row. A row spanning seasons uses its first.
    func historyPoster(for group: DiaryEpisodeGroup) -> String? {
        group.episodes.first.flatMap { seasonPosters[$0.seasonNumber] } ?? group.posterPath
    }

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
            let months = DiaryContent.months(
                from: entries,
                groupsEpisodes: scope?.subject.episode == nil,
                calendar: calendar,
                locale: locale
            )
            earlierRows = scope == nil ? [] : DiaryContent.earlierRows(from: entries, calendar: calendar, locale: locale)
            state = months.isEmpty && earlierRows.isEmpty ? .empty : .loaded(months)
            if showsSeasonPosters, let seriesID = scope?.subject.tmdbID {
                seasonPosters = await context.seasonPosters(seriesID: seriesID)
            }
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

    /// Opens the sheet for a new watch of the scoped title, dated today and unrated. The
    /// title snapshot comes from its latest entry, falling back to the screen's title.
    func beginRewatch() async {
        guard let scope, canLogRewatch else { return }
        let latest = try? await context.diary.entries(for: scope.subject).first
        let title = LogWatchTitle(
            subject: scope.subject,
            title: latest?.title ?? scope.title,
            releaseYear: latest?.releaseYear,
            posterPath: latest?.posterPath
        )
        editor = .logging(title, currentScore: nil, now: now())
    }

    /// Saves the open editor's draft. Success closes the sheet; failure keeps it open.
    func save(_ draft: DiaryEntryDraft) async -> AnnotationEditorWriteResult {
        guard let session = editor else { return .cancelled }
        do {
            try await context.save(session.entry(from: draft, now: now(), calendar: calendar))
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
            try await context.deleteWatch(session.base)
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
            try await context.deleteWatch(row.entry)
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

    private func fail(with error: AppError) {
        if case .loaded(let months, _) = state {
            state = .loaded(months, activity: .failed(error))
        } else {
            state = .failed(error)
        }
    }
}
