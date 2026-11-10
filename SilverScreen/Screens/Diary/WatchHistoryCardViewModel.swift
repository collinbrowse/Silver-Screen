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
/// and the last watch day. A show's history counts its episodes instead. The detail
/// screen shows the row only once there is history.
@Observable
@MainActor
final class WatchHistoryCardViewModel {
    /// Watch count and last day for the row's subtitle. Nil until loaded or when unreadable.
    private(set) var summary: String?
    private(set) var watchCount = 0
    /// Distinct episodes with a watch, for a show. Always 0 for a movie or an episode.
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
            watchCount = entries.count
            let episodes = subject.isWholeSeries ? entries.filter { $0.subject.episode != nil } : []
            episodeCount = Set(episodes.map(\.subject)).count
            // A show reads by its episodes; a whole-series entry only speaks when none exist.
            summary = Self.episodesSummary(for: episodes, calendar: calendar, locale: locale)
                ?? Self.summary(for: entries, calendar: calendar, locale: locale)
        } catch is CancellationError {
            return
        } catch {
            summary = nil
        }
    }

    /// "1 episode watched · Oct 16, 2026" or "12 episodes watched · last Oct 16, 2026".
    /// With rewatches: "12 episodes watched · 2 rewatches · last Oct 20, 2026". The day is
    /// left out when no watch has one. Nil when `entries` is empty.
    static func episodesSummary(for entries: [DiaryEntry], calendar: Calendar, locale: Locale) -> String? {
        let count = Set(entries.map(\.subject)).count
        guard count > 0 else { return nil }
        let watched = count == 1 ? String(localized: "1 episode watched") : String(localized: "\(count) episodes watched")
        let rewatches = DiaryContent.rewatchIDs(in: entries).count
        let day = lastDay(of: entries, calendar: calendar, locale: locale)
        switch rewatches {
            case 0:
                guard let day else { return watched }
                return count == 1 ? "\(watched) · \(day)" : String(localized: "\(watched) · last \(day)")
            case 1:
                return [watched, String(localized: "1 rewatch"), day.map { String(localized: "last \($0)") }].compactMap { $0 }.joined(separator: " · ")
            default:
                return [watched, String(localized: "\(rewatches) rewatches"), day.map { String(localized: "last \($0)") }]
                    .compactMap { $0 }
                    .joined(separator: " · ")
        }
    }

    /// "Watched once · Oct 16, 2026" or "Watched 3 times · last Oct 16, 2026", without
    /// the day when no watch has one.
    static func summary(for entries: [DiaryEntry], calendar: Calendar, locale: Locale) -> String? {
        guard !entries.isEmpty else { return nil }
        let day = lastDay(of: entries, calendar: calendar, locale: locale)
        if entries.count == 1 {
            return day.map { String(localized: "Watched once · \($0)") } ?? String(localized: "Watched once")
        }
        let times = String(localized: "Watched \(entries.count) times")
        return day.map { String(localized: "\(times) · last \($0)") } ?? times
    }

    /// The newest dated watch's day, formatted. Nil when every watch is undated.
    private static func lastDay(of entries: [DiaryEntry], calendar: Calendar, locale: Locale) -> String? {
        entries.filter(\.isDateKnown).map(\.watchedOn).max().map { latest in
            latest.date(in: calendar).formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            )
        }
    }
}
