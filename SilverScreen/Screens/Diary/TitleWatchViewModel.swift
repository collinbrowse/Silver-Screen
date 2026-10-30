//
//  TitleWatchViewModel.swift
//  SilverScreen
//

import Foundation

/// What a movie or episode page shows about your watches: the rating card, Log a Rewatch,
/// and your latest review. All three open the Log sheet, the only place a watch is edited.
/// Rating never records a watch: an unwatched title shows only its TMDB score.
@Observable
@MainActor
final class TitleWatchViewModel {
    /// Watches of exactly this title, newest first.
    private(set) var watches: [DiaryEntry] = []
    /// The open Log sheet, or nil.
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

    var isWatched: Bool { !watches.isEmpty }

    /// The watch the page's rating comes from.
    var ratedWatch: DiaryEntry? { WatchRepository.ratedWatch(in: watches) }

    /// "8.5"; nil until a watch has a rating.
    var formattedUserScore: String? {
        ratedWatch?.score.map { String(format: "%.1f", $0) }
    }

    /// "from your Oct 16 watch", or "from an earlier watch" when it has no date.
    var scoreCaption: String? {
        ratedWatch.map { "from \(watchName($0))" }
    }

    var scoreAccessibilityLabel: String {
        if let score = formattedUserScore, let scoreCaption {
            return "Your rating \(score), \(scoreCaption). Edit."
        }
        return watches.first.map { "Rate \(watchName($0))" } ?? "Add rating"
    }

    /// The newest watch with a review, which the page shows beside the overview.
    var reviewWatch: DiaryEntry? { watches.first { $0.review != nil } }

    /// The day `reviewWatch` was seen, for the review's caption. Nil when undated.
    var formattedReviewDay: String? {
        reviewWatch.flatMap(dayText)
    }

    /// Reloads `current` when it is for `title`, otherwise loads a new one. Nil when there
    /// is no title yet or no diary (previews). Pages call this when the diary changes.
    static func refreshed(
        _ current: TitleWatchViewModel?,
        title: LogWatchTitle?,
        context: DiaryContext?
    ) async -> TitleWatchViewModel? {
        guard let title, let context else { return nil }
        let viewModel: TitleWatchViewModel
        if let current, current.title.subject == title.subject {
            viewModel = current
        } else {
            viewModel = TitleWatchViewModel(title: title, context: context)
        }
        await viewModel.load()
        return viewModel
    }

    func load() async {
        do {
            let entries = try await context.diary.entries(for: title.subject)
            watches = entries.filter { $0.subject == title.subject }
        } catch is CancellationError {
            return
        } catch {
            watches = []
        }
    }

    /// Opens the watch the rating card names, or the newest when none is rated yet.
    func openRating() {
        guard let watch = ratedWatch ?? watches.first else { return }
        editor = .editing(watch, calendar: calendar)
    }

    func openReview() {
        guard let reviewWatch else { return }
        editor = .editing(reviewWatch, calendar: calendar)
    }

    /// Opens the Log sheet for a new, unrated watch dated today.
    func beginRewatch() {
        guard isWatched else { return }
        editor = .logging(title, currentScore: nil, now: now())
    }

    func dismissEditor() {
        editor = nil
    }

    /// Saves the open sheet. Failure keeps it open.
    func save(_ draft: DiaryEntryDraft) async -> AnnotationEditorWriteResult {
        guard let session = editor else { return .cancelled }
        do {
            try await context.save(session.entry(from: draft, now: now(), calendar: calendar))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        return await finishWrite()
    }

    /// Deletes the watch open in the sheet. Failure keeps it open.
    func deleteOpenWatch() async -> AnnotationEditorWriteResult {
        guard let session = editor, !session.isNew else { return .cancelled }
        do {
            try await context.deleteWatch(session.base)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        return await finishWrite()
    }

    private func finishWrite() async -> AnnotationEditorWriteResult {
        editor = nil
        await load()
        context.noteChange()
        return .succeeded
    }

    /// "your Oct 16 watch", or "an earlier watch" when it has no date.
    private func watchName(_ watch: DiaryEntry) -> String {
        dayText(watch).map { "your \($0) watch" } ?? "an earlier watch"
    }

    private func dayText(_ watch: DiaryEntry) -> String? {
        guard watch.isDateKnown else { return nil }
        return watch.watchedOn.date(in: calendar).formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        )
    }
}
