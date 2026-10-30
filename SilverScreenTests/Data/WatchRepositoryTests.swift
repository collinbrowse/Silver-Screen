//
//  WatchRepositoryTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class WatchRepositoryTests: XCTestCase {
    private let draft = ListItemDraft(
        id: 550,
        kind: .movie,
        title: "Fight Club",
        imagePath: nil,
        releaseDate: nil,
        genreNames: [],
        voteAverage: 8,
        popularity: 1
    )

    func test_logMovie_savesWatchAndAddsToWatched() async throws {
        let harness = Harness()

        let logged = try await harness.watches.logMovie(draft)

        XCTAssertEqual(logged.entry.subject, .movie(550))
        XCTAssertEqual(logged.membership.action, .added)
        let stored = await harness.diaryStore.entries
        XCTAssertEqual(stored, [logged.entry])
        let onWatched = try await harness.isOnWatched(draft)
        XCTAssertTrue(onWatched)
    }

    func test_logMovie_listFailure_removesTheWatch() async throws {
        let harness = Harness()
        _ = try await harness.lists.snapshot()
        await harness.listsStore.setSaveError(AppError.persistence)

        do {
            _ = try await harness.watches.logMovie(draft)
            XCTFail("Expected the list failure to propagate")
        } catch {
            let stored = await harness.diaryStore.entries
            XCTAssertTrue(stored.isEmpty)
        }
    }

    func test_removeMovie_deletesEveryWatchAndLeavesWatched() async throws {
        let harness = Harness()
        let first = try await harness.watches.logMovie(draft)
        try await harness.diary.save(DiaryFixtures.entry(subject: .movie(550)))
        let other = try await harness.diary.save(DiaryFixtures.entry(subject: .movie(1)))

        let removed = try await harness.watches.removeMovie(draft)

        XCTAssertEqual(removed.entries.count, 2)
        XCTAssertTrue(removed.entries.contains(first.entry))
        let stored = await harness.diaryStore.entries
        XCTAssertEqual(stored, [other])
        let onWatched = try await harness.isOnWatched(draft)
        XCTAssertFalse(onWatched)
    }

    func test_removeMovie_listFailure_restoresTheWatches() async throws {
        let harness = Harness()
        let logged = try await harness.watches.logMovie(draft)
        await harness.listsStore.setSaveError(AppError.persistence)

        do {
            _ = try await harness.watches.removeMovie(draft)
            XCTFail("Expected the list failure to propagate")
        } catch {
            let stored = await harness.diaryStore.entries
            XCTAssertEqual(stored, [logged.entry])
        }
    }

    func test_restore_bringsBackWatchesAndWatchedRow() async throws {
        let harness = Harness()
        let logged = try await harness.watches.logMovie(draft)
        let removed = try await harness.watches.removeMovie(draft)

        try await harness.watches.restore(removed)

        let stored = await harness.diaryStore.entries
        XCTAssertEqual(stored, [logged.entry])
        let onWatched = try await harness.isOnWatched(draft)
        XCTAssertTrue(onWatched)
    }

    func test_watches_ofSeries_leavesOutItsEpisodes() async throws {
        let harness = Harness()
        let series = try await harness.diary.save(DiaryFixtures.entry(subject: .series(9)))
        try await harness.diary.save(
            DiaryFixtures.entry(subject: .episode(seriesID: 9, season: 1, episode: 1))
        )

        let watches = try await harness.watches.watches(of: .series(9))

        XCTAssertEqual(watches, [series])
    }

    func test_logMovie_adoptsScoreAndNote_andUndoPutsThemBack() async throws {
        let harness = Harness()
        try await harness.annotations.save(score: 7, note: "Saw it in theaters", for: .movie(550))

        let logged = try await harness.watches.logMovie(draft)

        XCTAssertEqual(logged.entry.score, 7)
        XCTAssertEqual(logged.entry.review, "Saw it in theaters")
        let adopted = try await harness.annotations.annotation(for: .movie(550))
        XCTAssertEqual(adopted?.score, 7)
        XCTAssertNil(adopted?.note)

        try await harness.watches.undo(logged)

        let restored = try await harness.annotations.annotation(for: .movie(550))
        XCTAssertEqual(restored?.score, 7)
        XCTAssertEqual(restored?.note, "Saw it in theaters")
    }

    func test_deleteWatch_lastEpisodeWatch_unmarksProgress() async throws {
        let tvStore = InMemoryTVWatchStore()
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let diary = DiaryRepository(store: InMemoryDiaryStore(), logger: SilentLogger())
        let tvWatch = TVWatchRepository(store: tvStore, lists: lists, diary: diary, logger: SilentLogger())
        let watches = WatchRepository(diary: diary, lists: lists, tvWatch: tvWatch, logger: SilentLogger())
        let show = ListItemDraft(
            id: 42,
            kind: .tv,
            title: "Severance",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 8,
            popularity: 1
        )
        let season = TVSeasonSummary(
            id: 1,
            name: "Season 1",
            seasonNumber: 1,
            episodeCount: 2,
            airDate: nil,
            posterPath: nil
        )
        try await tvWatch.markSeries(seriesID: 42, seasons: [season], draft: show)
        let entries = try await diary.entries()

        try await watches.deleteWatch(try XCTUnwrap(entries.first))

        let completed = try await tvWatch.completedEpisodeCount(seriesID: 42)
        XCTAssertEqual(completed, 1)
        let snapshot = try await lists.snapshot()
        XCTAssertEqual(snapshot.entries.first?.listID, snapshot.list(.inProgress)?.id)

        try await watches.deleteWatch(try XCTUnwrap(entries.last))

        let cleared = try await tvWatch.state(seriesID: 42)
        XCTAssertNil(cleared)
        let after = try await lists.snapshot()
        XCTAssertTrue(after.entries.isEmpty)
    }

    func test_logSeasonRewatch_addsOneWatchPerEpisodeInOneWrite_andUndoRemovesThem() async throws {
        let harness = Harness()

        let logged = try await harness.watches.logSeasonRewatch(
            seriesID: 42,
            season: 1,
            episodes: [1, 2, 3],
            title: "Severance",
            posterPath: nil,
            on: Date(),
            dateKnown: true
        )

        XCTAssertEqual(logged.count, 3)
        XCTAssertEqual(Set(logged.map(\.loggedAt)).count, 1)
        let saves = await harness.diaryStore.saveCount
        XCTAssertEqual(saves, 1)

        try await harness.watches.undo(seasonRewatch: logged)

        let stored = await harness.diaryStore.entries
        XCTAssertTrue(stored.isEmpty)
    }

    func test_ratedWatch_skipsNewerUnratedWatch() {
        let unrated = DiaryFixtures.entry()
        let rated = DiaryFixtures.entry(score: 8.5)

        XCTAssertEqual(WatchRepository.ratedWatch(in: [unrated, rated]), rated)
    }

    func test_ratedWatch_noScores_isNil() {
        XCTAssertNil(WatchRepository.ratedWatch(in: [DiaryFixtures.entry()]))
    }

    func test_deleteWatch_ratingFallsBackToOlderRatedWatch() async throws {
        let harness = Harness()
        let older = DiaryFixtures.entry(watchedOn: DiaryDay(year: 2026, month: 1, day: 1), score: 6)
        let newer = DiaryFixtures.entry(watchedOn: DiaryDay(year: 2026, month: 2, day: 1), score: 9)
        try await harness.diary.save(contentsOf: [older, newer])
        try await harness.annotations.saveScore(9, for: .movie(550))

        try await harness.watches.deleteWatch(newer)

        let rating = try await harness.annotations.annotation(for: .movie(550))
        XCTAssertEqual(rating?.score, 6)
    }

    func test_deleteWatch_lastWatch_leavesWatchedAndClearsRating() async throws {
        let harness = Harness()
        let logged = try await harness.watches.logMovie(draft)
        try await harness.annotations.saveScore(7, for: .movie(550))

        try await harness.watches.deleteWatch(logged.entry)

        let onWatched = try await harness.isOnWatched(draft)
        XCTAssertFalse(onWatched)
        let rating = try await harness.annotations.annotation(for: .movie(550))
        XCTAssertNil(rating)
    }

    func test_syncRating_seriesSubject_leavesVerdictAlone() async throws {
        let harness = Harness()
        try await harness.annotations.saveScore(7, for: .series(9))

        try await harness.annotations.syncRating(from: nil, for: .series(9))

        let verdict = try await harness.annotations.annotation(for: .series(9))
        XCTAssertEqual(verdict?.score, 7)
    }

    func test_diarySaveContentsOf_writesOnceAndReplacesByID() async throws {
        var existing = DiaryFixtures.entry(score: 6)
        let store = InMemoryDiaryStore(entries: [existing])
        let diary = DiaryRepository(store: store, logger: SilentLogger())
        existing.score = 9
        let added = DiaryFixtures.entry(subject: .movie(1))

        try await diary.save(contentsOf: [existing, added])

        let stored = await store.entries
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first?.score, 9)
        let saves = await store.saveCount
        XCTAssertEqual(saves, 1)
    }

    func test_diaryDeleteIDs_writesOnce() async throws {
        let first = DiaryFixtures.entry()
        let second = DiaryFixtures.entry()
        let store = InMemoryDiaryStore(entries: [first, second])
        let diary = DiaryRepository(store: store, logger: SilentLogger())

        try await diary.delete(ids: [first.id, second.id])

        let stored = await store.entries
        XCTAssertTrue(stored.isEmpty)
        let saves = await store.saveCount
        XCTAssertEqual(saves, 1)
    }
}

@MainActor
private struct Harness {
    let diaryStore = InMemoryDiaryStore()
    let listsStore = InMemoryListsStore()
    let diary: DiaryRepository
    let lists: ListsRepository
    let annotations: AnnotationsRepository
    let watches: WatchRepository

    init() {
        diary = DiaryRepository(store: diaryStore, logger: SilentLogger())
        lists = ListsRepository(store: listsStore, logger: SilentLogger())
        annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        watches = WatchRepository(diary: diary, lists: lists, annotations: annotations, logger: SilentLogger())
    }

    func isOnWatched(_ draft: ListItemDraft) async throws -> Bool {
        let snapshot = try await lists.snapshot()
        guard let watched = snapshot.list(.watched) else { return false }
        return snapshot.entries.contains { $0.listID == watched.id && $0.itemKey == draft.itemKey }
    }
}
