//
//  LogWatchViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class LogWatchViewModelTests: XCTestCase {
    /// Fri 16 Oct 2026, 18:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_173_600)

    func test_load_withNoEntries_offersFirstWatch() async {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())

        await viewModel.load()

        XCTAssertEqual(viewModel.watchCount, 0)
        XCTAssertNil(viewModel.summary)
        XCTAssertEqual(viewModel.actionTitle, "Log a watch")
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
        XCTAssertEqual(viewModel.summary, "Watched 2 times · last Oct 3, 2026")
        XCTAssertEqual(viewModel.actionTitle, "Log a rewatch")
    }

    func test_summary_singleEntry_saysOnce() {
        let summary = LogWatchViewModel.summary(
            for: [DiaryFixtures.entry()],
            calendar: DiaryFixtures.utcCalendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(summary, "Watched once · Oct 16, 2026")
    }

    func test_beginLog_firstWatch_prefillsTodayAndRating() async throws {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())
        await viewModel.load()

        viewModel.beginLog(currentScore: 8.5)

        let session = try XCTUnwrap(viewModel.editor)
        XCTAssertTrue(session.isNew)
        XCTAssertFalse(session.canDelete)
        XCTAssertEqual(session.title, "Fight Club")
        XCTAssertEqual(session.draft.score, 8.5)
        XCTAssertEqual(session.draft.watchedOn, now)
    }

    func test_save_afterEarlierWatch_storesNoManualRewatchFlag() async throws {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry(subject: .movie(550))])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        viewModel.beginLog(currentScore: nil)

        _ = await viewModel.save(try XCTUnwrap(viewModel.editor?.draft))

        let stored = await store.entries
        XCTAssertEqual(stored.map(\.isRewatch), [false, false])
    }

    func test_beginLog_invalidCurrentScore_isNotPrefilled() {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())

        viewModel.beginLog(currentScore: 0)

        XCTAssertNil(viewModel.editor?.draft.score)
    }

    func test_save_storesEntryWithTitleSnapshot() async throws {
        let store = InMemoryDiaryStore()
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        viewModel.beginLog(currentScore: nil)
        var draft = try XCTUnwrap(viewModel.editor?.draft)
        draft.score = 7
        draft.review = "  Still great.  "
        draft.tagsText = "rewatch-worthy, friends"

        let result = await viewModel.save(draft)

        XCTAssertEqual(result, .succeeded)
        let entries = await store.entries
        let stored = try XCTUnwrap(entries.first)
        XCTAssertEqual(stored.subject, .movie(550))
        XCTAssertEqual(stored.title, "Fight Club")
        XCTAssertEqual(stored.releaseYear, 1999)
        XCTAssertEqual(stored.posterPath, "/fc.jpg")
        XCTAssertEqual(stored.watchedOn, DiaryDay(year: 2026, month: 10, day: 16))
        XCTAssertEqual(stored.score, 7)
        XCTAssertEqual(stored.review, "Still great.")
        XCTAssertEqual(stored.tags, ["rewatch-worthy", "friends"])
        XCTAssertEqual(stored.loggedAt, now)
    }

    func test_save_putsTitleOnWatchedClosesEditorAndNotesChange() async throws {
        let lists = ListsRepository.empty()
        let context = DiaryContext(
            diary: DiaryRepository(store: InMemoryDiaryStore(), logger: SilentLogger()),
            lists: lists,
            logger: SilentLogger()
        )
        let viewModel = makeViewModel(context: context)
        viewModel.beginLog(currentScore: nil)

        let result = await viewModel.save(try XCTUnwrap(viewModel.editor?.draft))

        XCTAssertEqual(result, .succeeded)
        XCTAssertNil(viewModel.editor)
        XCTAssertEqual(context.revision, 1)
        XCTAssertEqual(viewModel.summary, "Watched once · Oct 16, 2026")
        let snapshot = try await lists.snapshot()
        let watchedID = try XCTUnwrap(snapshot.list(.watched)?.id)
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watchedID && $0.itemKey == "movie-550" })
    }

    func test_save_whenDiaryFails_keepsEditorAndLeavesWatchedAlone() async throws {
        let store = InMemoryDiaryStore()
        await store.setSaveError(CocoaError(.fileWriteUnknown))
        let lists = ListsRepository.empty()
        let context = DiaryContext(
            diary: DiaryRepository(store: store, logger: SilentLogger()),
            lists: lists,
            logger: SilentLogger()
        )
        let viewModel = makeViewModel(context: context)
        viewModel.beginLog(currentScore: nil)

        let result = await viewModel.save(try XCTUnwrap(viewModel.editor?.draft))

        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(viewModel.editor)
        XCTAssertEqual(context.revision, 0)
        let snapshot = try await lists.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    func test_save_whenWatchedFails_keepsEntry() async throws {
        let diaryStore = InMemoryDiaryStore()
        let listsStore = InMemoryListsStore()
        await listsStore.setSaveError(CocoaError(.fileWriteUnknown))
        let context = DiaryContext(
            diary: DiaryRepository(store: diaryStore, logger: SilentLogger()),
            lists: ListsRepository(store: listsStore, logger: SilentLogger()),
            logger: SilentLogger()
        )
        let viewModel = makeViewModel(context: context)
        viewModel.beginLog(currentScore: nil)

        let result = await viewModel.save(try XCTUnwrap(viewModel.editor?.draft))

        XCTAssertEqual(result, .succeeded)
        let stored = await diaryStore.entries
        XCTAssertEqual(stored.count, 1)
    }

    func test_load_withNoHistory_hidesHistoryRow() async {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())

        await viewModel.load()

        XCTAssertFalse(viewModel.hasHistory)
    }

    func test_load_withEntries_offersHistoryRouteForTitle() async {
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [DiaryFixtures.entry(subject: .movie(550))]))

        await viewModel.load()

        XCTAssertTrue(viewModel.hasHistory)
        XCTAssertEqual(viewModel.historyRoute, .titleHistory(kind: .movie, id: 550, title: "Fight Club"))
    }

    func test_load_seriesWithOnlyEpisodes_summarizesEpisodes() async {
        let store = InMemoryDiaryStore(episodeWatches: [
            episodeWatch(series: 42, episode: 1, at: Date(timeIntervalSince1970: 1_792_000_000)),
            episodeWatch(series: 42, episode: 2, at: now),
            episodeWatch(series: 7, episode: 1, at: now),
        ])
        let viewModel = makeViewModel(store: store, title: seriesTitle)

        await viewModel.load()

        XCTAssertEqual(viewModel.watchCount, 0)
        XCTAssertEqual(viewModel.episodeCount, 2)
        XCTAssertTrue(viewModel.hasHistory)
        XCTAssertEqual(viewModel.summary, "2 episodes watched · last Oct 16, 2026")
        XCTAssertEqual(viewModel.actionTitle, "Log a watch")
    }

    func test_load_movie_ignoresEpisodeHistory() async {
        let store = InMemoryDiaryStore(episodeWatches: [episodeWatch(series: 550, episode: 1, at: now)])
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.episodeCount, 0)
        XCTAssertFalse(viewModel.hasHistory)
    }

    func test_save_series_leavesListsAlone() async throws {
        let lists = ListsRepository.empty()
        let diaryStore = InMemoryDiaryStore()
        let context = DiaryContext(
            diary: DiaryRepository(store: diaryStore, logger: SilentLogger()),
            lists: lists,
            logger: SilentLogger()
        )
        let viewModel = makeViewModel(context: context, title: seriesTitle)
        viewModel.beginLog(currentScore: nil)

        let result = await viewModel.save(try XCTUnwrap(viewModel.editor?.draft))

        XCTAssertEqual(result, .succeeded)
        let stored = await diaryStore.entries
        XCTAssertEqual(stored.map(\.subject), [.series(42)])
        let snapshot = try await lists.snapshot()
        XCTAssertFalse(snapshot.entries.contains { $0.itemKey == "tv-42" })
    }

    // MARK: - Helpers

    private var seriesTitle: LogWatchTitle {
        LogWatchTitle(
            subject: .series(42),
            title: "Severance",
            releaseYear: 2022,
            posterPath: "/sev.jpg",
            listItem: ListItemDraft(
                id: 42,
                kind: .tv,
                title: "Severance",
                imagePath: "/sev.jpg",
                releaseDate: nil,
                genreNames: [],
                voteAverage: 8,
                popularity: 10
            )
        )
    }

    private func episodeWatch(series: Int, episode: Int, at date: Date) -> EpisodeWatch {
        EpisodeWatch(
            seriesID: series,
            seriesTitle: "Show \(series)",
            posterPath: nil,
            episode: TVEpisodeRef(seasonNumber: 1, episodeNumber: episode),
            completedAt: date
        )
    }

    private var title: LogWatchTitle {
        LogWatchTitle(
            subject: .movie(550),
            title: "Fight Club",
            releaseYear: 1999,
            posterPath: "/fc.jpg",
            listItem: ListItemDraft(
                id: 550,
                kind: .movie,
                title: "Fight Club",
                imagePath: "/fc.jpg",
                releaseDate: nil,
                genreNames: ["Drama"],
                voteAverage: 8.4,
                popularity: 40
            )
        )
    }

    private func makeViewModel(store: InMemoryDiaryStore, title: LogWatchTitle? = nil) -> LogWatchViewModel {
        makeViewModel(
            context: DiaryContext(
                diary: DiaryRepository(store: store, logger: SilentLogger()),
                lists: ListsRepository.empty(),
                logger: SilentLogger()
            ),
            title: title
        )
    }

    private func makeViewModel(context: DiaryContext, title: LogWatchTitle? = nil) -> LogWatchViewModel {
        let now = now
        return LogWatchViewModel(
            title: title ?? self.title,
            context: context,
            calendar: DiaryFixtures.utcCalendar,
            locale: Locale(identifier: "en_US"),
            now: { now }
        )
    }
}
