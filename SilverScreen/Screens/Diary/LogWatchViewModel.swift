//
//  LogWatchViewModel.swift
//  SilverScreen
//

import Foundation

/// "Log a watch" on a title's detail screen: how many times it has been logged, the
/// last watch day, the way into the title's watch history, and the editor for a new
/// entry. A show's history also counts its checked-off episodes. Saving also puts a movie on
/// Watched; if only that second step fails the entry is kept and the failure is logged,
/// because the diary is what the person asked to change.
@Observable
@MainActor
final class LogWatchViewModel {
    /// Watch count and last day for the row's subtitle. Nil until loaded or when unreadable.
    private(set) var summary: String?
    private(set) var watchCount = 0
    /// Checked-off episodes, for a show. Always 0 for a movie.
    private(set) var episodeCount = 0
    var editor: DiaryEditorSession?

    let title: LogWatchTitle
    private let context: DiaryContext
    private let calendar: Calendar
    private let locale: Locale
    private let now: @Sendable () -> Date

    init(
        title: LogWatchTitle,
        context: DiaryContext,
        calendar: Calendar = .current,
        locale: Locale = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.title = title
        self.context = context
        self.calendar = calendar
        self.locale = locale
        self.now = now
    }

    var contextRevision: Int { context.revision }

    /// "Log a watch" for a first viewing, "Log a rewatch" once the title has entries.
    var actionTitle: String {
        watchCount == 0 ? "Log a watch" : "Log a rewatch"
    }

    /// Whether there is anything to show in the title's watch history.
    var hasHistory: Bool {
        watchCount > 0 || episodeCount > 0
    }

    /// The title's watch history screen.
    var historyRoute: Route {
        .titleHistory(kind: title.subject.kind, id: title.subject.tmdbID, title: title.title)
    }

    func load() async {
        do {
            let entries = try await context.diary.entries(for: title.subject)
            let episodes = try await episodeWatches()
            watchCount = entries.count
            episodeCount = episodes.count
            summary = Self.summary(for: entries, calendar: calendar, locale: locale)
                ?? Self.episodesSummary(for: episodes, calendar: calendar, locale: locale)
        } catch is CancellationError {
            return
        } catch {
            summary = nil
        }
    }

    /// Opens the editor dated today, prefilled with the title's current rating.
    func beginLog(currentScore: Double?) {
        editor = .logging(title, currentScore: currentScore, now: now())
    }

    func dismissEditor() {
        editor = nil
    }

    func save(_ draft: DiaryEntryDraft) async -> AnnotationEditorWriteResult {
        guard let session = editor else { return .cancelled }
        let entry = session.entry(from: draft, now: now(), calendar: calendar)
        do {
            try await context.diary.save(entry)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        // A show's Watched and In Progress membership follow its episode progress, so a
        // logged watch of a show (say, a review mid-season) leaves its lists alone.
        if title.subject.kind == .movie {
            do {
                _ = try await context.lists.addToWatched(title.listItem, at: entry.watchedOn.date(in: calendar))
            } catch is CancellationError {
                // The entry is saved; Watched catches up next time.
            } catch {
                context.logger.error("Logged watch was not added to Watched", category: .persistence)
            }
        }
        editor = nil
        context.noteChange()
        await load()
        return .succeeded
    }

    /// The show's checked-off episodes, or none for a movie or when they cannot be read
    /// (the repository logs that). Only cancellation propagates.
    private func episodeWatches() async throws -> [EpisodeWatch] {
        guard title.subject.kind == .tv else { return [] }
        do {
            return try await context.diary.episodeWatches(seriesID: title.subject.tmdbID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    /// "1 episode watched · Oct 16, 2026" or "12 episodes watched · last Oct 16, 2026",
    /// for a show with check-offs but no logged watch.
    static func episodesSummary(for episodes: [EpisodeWatch], calendar: Calendar, locale: Locale) -> String? {
        guard let latest = episodes.map(\.completedAt).max() else { return nil }
        let day = DiaryDay(latest, calendar: calendar).date(in: calendar).formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
        if episodes.count == 1 {
            return "1 episode watched · \(day)"
        }
        return "\(episodes.count) episodes watched · last \(day)"
    }

    /// "Watched once · Oct 16, 2026" or "Watched 3 times · last Oct 16, 2026".
    static func summary(for entries: [DiaryEntry], calendar: Calendar, locale: Locale) -> String? {
        guard let latest = entries.map(\.watchedOn).max() else { return nil }
        let day = latest.date(in: calendar).formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
        if entries.count == 1 {
            return "Watched once · \(day)"
        }
        return "Watched \(entries.count) times · last \(day)"
    }
}
