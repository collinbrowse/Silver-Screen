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
    let watches: WatchRepository

    init() {
        diary = DiaryRepository(store: diaryStore, logger: SilentLogger())
        lists = ListsRepository(store: listsStore, logger: SilentLogger())
        watches = WatchRepository(diary: diary, lists: lists, logger: SilentLogger())
    }

    func isOnWatched(_ draft: ListItemDraft) async throws -> Bool {
        let snapshot = try await lists.snapshot()
        guard let watched = snapshot.list(.watched) else { return false }
        return snapshot.entries.contains { $0.listID == watched.id && $0.itemKey == draft.itemKey }
    }
}
