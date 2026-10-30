//
//  WatchHistoryCardViewModel.swift
//  SilverScreen
//

import Foundation

/// What a detail screen's Watch History reloads on: the title once loaded, and the
/// diary's revision so a watch logged anywhere shows up.
struct WatchHistoryLoadKey: Equatable {
    let subject: DiarySubject?
    let revision: Int?
}

/// The Watch History row on a title's detail screen: how many times it has been logged
/// and the last watch day. A show's history also counts its checked-off episodes. The
/// detail screen shows the row only once there is history; watches themselves come from
/// the eye (and, for a movie, Log a Rewatch on the history screen).
@Observable
@MainActor
final class WatchHistoryCardViewModel {
    /// Watch count and last day for the row's subtitle. Nil until loaded or when unreadable.
    private(set) var summary: String?
    private(set) var watchCount = 0
    /// Checked-off episodes, for a show. Always 0 for a movie.
    private(set) var episodeCount = 0

    let subject: DiarySubject
    private let context: DiaryContext
    private let calendar: Calendar
    private let locale: Locale

    init(
        subject: DiarySubject,
        context: DiaryContext,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.subject = subject
        self.context = context
        self.calendar = calendar
        self.locale = locale
    }

    /// Whether the detail screen shows the row at all.
    var hasHistory: Bool {
        watchCount > 0 || episodeCount > 0
    }

    /// Reloads `current` when it is for `subject`, otherwise loads a new one. Nil when
    /// there is no subject yet (the title is still loading) or no diary (previews).
    /// Detail screens call this whenever the title or the diary's revision changes.
    static func refreshed(
        _ current: WatchHistoryCardViewModel?,
        subject: DiarySubject?,
        context: DiaryContext?
    ) async -> WatchHistoryCardViewModel? {
        guard let subject, let context else { return nil }
        let viewModel: WatchHistoryCardViewModel
        if let current, current.subject == subject {
            viewModel = current
        } else {
            viewModel = WatchHistoryCardViewModel(subject: subject, context: context)
        }
        await viewModel.load()
        return viewModel
    }

    func load() async {
        do {
            let entries = try await context.diary.entries(for: subject)
            let episodes = try await episodeWatches()
            watchCount = entries.count
            episodeCount = episodes.count
            // A show reads by its episodes plus their rewatches; a whole-series entry
            // (imported) only speaks when nothing was checked off.
            if subject.kind == .tv {
                let rewatches = entries.filter { $0.subject.episode != nil }
                summary = Self.episodesSummary(
                    for: episodes,
                    rewatches: rewatches.map(\.watchedOn),
                    calendar: calendar,
                    locale: locale
                ) ?? Self.summary(for: entries, calendar: calendar, locale: locale)
            } else {
                summary = Self.summary(for: entries, calendar: calendar, locale: locale)
            }
        } catch is CancellationError {
            return
        } catch {
            summary = nil
        }
    }

    /// The show's checked-off episodes, or none for a movie or when they cannot be read
    /// (the repository logs that). Only cancellation propagates.
    private func episodeWatches() async throws -> [EpisodeWatch] {
        guard subject.kind == .tv else { return [] }
        do {
            return try await context.diary.episodeWatches(seriesID: subject.tmdbID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    /// "1 episode watched · Oct 16, 2026" or "12 episodes watched · last Oct 16, 2026".
    /// With rewatches: "12 episodes watched · 2 rewatches · last Oct 20, 2026", where the
    /// last day counts them too. Nil when nothing was checked off.
    static func episodesSummary(
        for episodes: [EpisodeWatch],
        rewatches: [DiaryDay] = [],
        calendar: Calendar,
        locale: Locale
    ) -> String? {
        let days = episodes.map { DiaryDay($0.completedAt, calendar: calendar) } + rewatches
        guard !episodes.isEmpty, let latest = days.max() else { return nil }
        let day = latest.date(in: calendar).formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
        let watched = episodes.count == 1 ? "1 episode watched" : "\(episodes.count) episodes watched"
        switch rewatches.count {
            case 0:
                return episodes.count == 1 ? "\(watched) · \(day)" : "\(watched) · last \(day)"
            case 1:
                return "\(watched) · 1 rewatch · last \(day)"
            default:
                return "\(watched) · \(rewatches.count) rewatches · last \(day)"
        }
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
