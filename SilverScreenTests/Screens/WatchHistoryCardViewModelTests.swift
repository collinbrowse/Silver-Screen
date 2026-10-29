//
//  WatchHistoryCardViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class WatchHistoryCardViewModelTests: XCTestCase {
    /// Fri 16 Oct 2026, 18:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_173_600)

    func test_load_withNoHistory_hidesCard() async {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())

        await viewModel.load()

        XCTAssertEqual(viewModel.watchCount, 0)
        XCTAssertNil(viewModel.summary)
        XCTAssertFalse(viewModel.hasHistory)
    }

    func test_load_withEntries_summarizesCountAndLastDay() async {
        let store = InMemoryDiaryStore(entries: [
            DiaryFixtures.entry(subject: .movie(550), watchedOn: DiaryDay(year: 2025, month: 1, day: 2)),
            DiaryFixtures.entry(subject: .movie(550), watchedOn: DiaryDay(year: 2026, month: 10, day: 3)),
            DiaryFixtures.entry(subject: .movie(1), watchedOn: DiaryDay(year: 2026, month: 10, day: 9)),
        ])
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.watchCount, 2)
        XCTAssertTrue(viewModel.hasHistory)
        XCTAssertEqual(viewModel.summary, "Watched 2 times · last Oct 3, 2026")
    }

    func test_summary_singleEntry_saysOnce() {
        let summary = WatchHistoryCardViewModel.summary(
            for: [DiaryFixtures.entry()],
            calendar: DiaryFixtures.utcCalendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(summary, "Watched once · Oct 16, 2026")
    }

    func test_load_seriesWithOnlyEpisodes_summarizesEpisodes() async {
        let store = InMemoryDiaryStore(episodeWatches: [
            episodeWatch(series: 42, episode: 1, at: Date(timeIntervalSince1970: 1_792_000_000)),
            episodeWatch(series: 42, episode: 2, at: now),
            episodeWatch(series: 7, episode: 1, at: now),
        ])
        let viewModel = makeViewModel(store: store, subject: .series(42))

        await viewModel.load()

        XCTAssertEqual(viewModel.watchCount, 0)
        XCTAssertEqual(viewModel.episodeCount, 2)
        XCTAssertTrue(viewModel.hasHistory)
        XCTAssertEqual(viewModel.summary, "2 episodes watched · last Oct 16, 2026")
    }

    func test_load_movie_ignoresEpisodeHistory() async {
        let store = InMemoryDiaryStore(episodeWatches: [episodeWatch(series: 550, episode: 1, at: now)])
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.episodeCount, 0)
        XCTAssertFalse(viewModel.hasHistory)
    }

    func test_refreshed_withoutSubjectOrDiary_isNil() async {
        let context = makeContext(store: InMemoryDiaryStore())

        let noSubject = await WatchHistoryCardViewModel.refreshed(nil, subject: nil, context: context)
        let noDiary = await WatchHistoryCardViewModel.refreshed(nil, subject: .movie(550), context: nil)

        XCTAssertNil(noSubject)
        XCTAssertNil(noDiary)
    }

    func test_refreshed_sameSubject_reusesAndPicksUpNewWatch() async throws {
        let context = makeContext(store: InMemoryDiaryStore())
        let loaded = await WatchHistoryCardViewModel.refreshed(nil, subject: .movie(550), context: context)
        let first = try XCTUnwrap(loaded)
        XCTAssertFalse(first.hasHistory)
        try await context.diary.save(DiaryFixtures.entry(subject: .movie(550)))

        let second = await WatchHistoryCardViewModel.refreshed(first, subject: .movie(550), context: context)

        XCTAssertTrue(second === first)
        XCTAssertTrue(first.hasHistory)
    }

    func test_refreshed_otherSubject_startsFresh() async throws {
        let context = makeContext(store: InMemoryDiaryStore())
        let movie = await WatchHistoryCardViewModel.refreshed(nil, subject: .movie(550), context: context)

        let show = await WatchHistoryCardViewModel.refreshed(movie, subject: .series(42), context: context)

        XCTAssertFalse(show === movie)
        XCTAssertEqual(show?.subject, .series(42))
    }

    // MARK: - Helpers

    private func episodeWatch(series: Int, episode: Int, at date: Date) -> EpisodeWatch {
        EpisodeWatch(
            seriesID: series,
            seriesTitle: "Show \(series)",
            posterPath: nil,
            episode: TVEpisodeRef(seasonNumber: 1, episodeNumber: episode),
            completedAt: date
        )
    }

    private func makeContext(store: InMemoryDiaryStore) -> DiaryContext {
        DiaryContext(
            diary: DiaryRepository(store: store, logger: SilentLogger()),
            lists: ListsRepository.empty(),
            logger: SilentLogger()
        )
    }

    private func makeViewModel(
        store: InMemoryDiaryStore,
        subject: DiarySubject = .movie(550)
    ) -> WatchHistoryCardViewModel {
        WatchHistoryCardViewModel(
            subject: subject,
            context: makeContext(store: store),
            calendar: DiaryFixtures.utcCalendar,
            locale: Locale(identifier: "en_US")
        )
    }
}
