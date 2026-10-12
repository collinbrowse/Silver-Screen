//
//  TVWatchRepositoryTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class TVWatchRepositoryTests: XCTestCase {
    func test_markEpisode_addsSeriesToInProgressAndClearsWatchlist() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 42, title: "Severance")
        let seeded = try await lists.snapshot()
        let watchlist = try XCTUnwrap(seeded.list(.watchlist))
        _ = try await lists.add(draft: draft, listID: watchlist.id)

        let seasons = [season(1, episodes: 3)]
        let outcome = try await tvWatch.markEpisode(
            seriesID: 42,
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Good News About Hell",
            draft: draft,
            seasons: seasons
        )

        let snapshot = try await lists.snapshot()
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == inProgress.id && $0.itemID == 42 })
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watchlist.id && $0.itemID == 42 })
        XCTAssertEqual(outcome.state.nextUp, TVEpisodeRef(seasonNumber: 1, episodeNumber: 2))
        XCTAssertEqual(outcome.state.progressSubtitle, "Next up: S1 · E2")
        XCTAssertEqual(outcome.membershipChange?.listName, "In Progress")
    }

    func test_markLastEpisode_movesSeriesToWatched() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 7, title: "Mini")
        let seasons = [season(1, episodes: 2)]

        _ = try await tvWatch.markEpisode(
            seriesID: 7,
            seasonNumber: 1,
            episodeNumber: 1,
            title: "One",
            draft: draft,
            seasons: seasons
        )
        let outcome = try await tvWatch.markEpisode(
            seriesID: 7,
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Two",
            draft: draft,
            seasons: seasons
        )

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 7 })
        XCTAssertFalse(snapshot.entries.contains { $0.listID == inProgress.id && $0.itemID == 7 })
        XCTAssertNotNil(outcome.state.catalogSnapshot)
        XCTAssertEqual(outcome.membershipChange?.messageOverride, "Mini moved to Watched")
    }

    func test_markSeries_bulkCompletesAndWatches() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 9, title: "Bulk")
        let seasons = [season(1, episodes: 2), season(2, episodes: 2)]

        let outcome = try await tvWatch.markSeries(seriesID: 9, seasons: seasons, draft: draft)

        XCTAssertEqual(outcome.episodesNewlyMarked, 4)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 9 })
    }

    func test_clearSeries_removesProgressAndWatchedMembership() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 11, title: "Clear Me")
        let seasons = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 11, seasons: seasons, draft: draft)

        let outcome = try await tvWatch.clearSeries(seriesID: 11, draft: draft)

        XCTAssertEqual(outcome.membershipChange?.action, .removed)
        let cleared = try await tvWatch.state(seriesID: 11)
        XCTAssertNil(cleared)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 11 })
    }

    func test_reconcileCatalog_movesBackToInProgress() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 3, title: "Returning")
        let finished = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 3, seasons: finished, draft: draft)

        let grown = [season(1, episodes: 1), season(2, episodes: 4)]
        let outcome = try await tvWatch.reconcileCatalog(
            seriesID: 3,
            seasons: grown,
            draft: draft
        )

        XCTAssertNotNil(outcome)
        let snapshot = try await lists.snapshot()
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == inProgress.id && $0.itemID == 3 })
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 3 })
    }

    func test_ensuringSystemLists_includesInProgress() async throws {
        let lists = makeLists()
        let snapshot = try await lists.snapshot()
        XCTAssertEqual(snapshot.list(.inProgress)?.name, "In Progress")
        let ordered = snapshot.lists(in: .moviesAndTV).compactMap(\.system)
        XCTAssertEqual(ordered, [.watched, .inProgress, .watchlist])
    }

    func test_undo_watchedMove_restoresInProgressAndLedger() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 12, title: "Two Step")
        let seasons = [season(1, episodes: 2)]

        _ = try await tvWatch.markEpisode(
            seriesID: 12,
            seasonNumber: 1,
            episodeNumber: 1,
            title: "A",
            draft: draft,
            seasons: seasons
        )
        let complete = try await tvWatch.markEpisode(
            seriesID: 12,
            seasonNumber: 1,
            episodeNumber: 2,
            title: "B",
            draft: draft,
            seasons: seasons
        )
        let move = try XCTUnwrap(complete.membershipChange)
        let watchUndo = try XCTUnwrap(complete.watchUndo)

        try await tvWatch.restore(watchUndo)
        try await lists.undo(move)

        let after = try await lists.snapshot()
        let inProgress = try XCTUnwrap(after.list(.inProgress))
        let watched = try XCTUnwrap(after.list(.watched))
        XCTAssertTrue(after.entries.contains { $0.listID == inProgress.id && $0.itemID == 12 })
        XCTAssertFalse(after.entries.contains { $0.listID == watched.id && $0.itemID == 12 })

        let restored = try await tvWatch.state(seriesID: 12)
        let state = try XCTUnwrap(restored)
        XCTAssertFalse(state.isSeriesComplete(against: seasons))
        XCTAssertNil(state.catalogSnapshot)
        XCTAssertEqual(state.nextUp, TVEpisodeRef(seasonNumber: 1, episodeNumber: 2))
        let unmarked = try await tvWatch.unmarkedEpisodeCount(seriesID: 12, seasons: seasons)
        XCTAssertEqual(unmarked, 1)
    }

    func test_load_duplicateSeriesIDs_mergesWithoutCrashing() async throws {
        let lists = makeLists()
        let first = TVSeriesWatchState(
            seriesID: 5,
            completed: [TVEpisodeRef(seasonNumber: 1, episodeNumber: 1)]
        )
        var second = TVSeriesWatchState(seriesID: 5)
        second.mark(seasonNumber: 1, episodeNumber: 2)
        let store = InMemoryTVWatchStore(states: [first, second])
        let tvWatch = TVWatchRepository(store: store, lists: lists, logger: SilentLogger())

        let loaded = try await tvWatch.state(seriesID: 5)
        let state = try XCTUnwrap(loaded)
        XCTAssertTrue(state.contains(seasonNumber: 1, episodeNumber: 1))
        XCTAssertTrue(state.contains(seasonNumber: 1, episodeNumber: 2))
    }

    func test_markSeason_whenAlreadyComplete_doesNotToastAgain() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 8, title: "Done")
        let seasons = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 8, seasons: seasons, draft: draft)

        let again = try await tvWatch.markSeason(
            seriesID: 8,
            seasonNumber: 1,
            episodeCount: 1,
            draft: draft,
            seasons: seasons
        )

        XCTAssertNil(again.membershipChange)
        XCTAssertEqual(again.episodesNewlyMarked, 0)
    }

    func test_unmarkLastEpisode_clearsWatchedMembership() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 4, title: "One Shot")
        let seasons = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 4, seasons: seasons, draft: draft)

        _ = try await tvWatch.unmarkEpisode(
            seriesID: 4,
            seasonNumber: 1,
            episodeNumber: 1,
            draft: draft,
            seasons: seasons
        )

        let cleared = try await tvWatch.state(seriesID: 4)
        XCTAssertNil(cleared)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 4 })
        XCTAssertFalse(snapshot.entries.contains { $0.listID == inProgress.id && $0.itemID == 4 })
    }

    func test_reconcileCatalog_sameCatalog_isNoOp() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 6, title: "Stable")
        let seasons = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 6, seasons: seasons, draft: draft)

        let outcome = try await tvWatch.reconcileCatalog(
            seriesID: 6,
            seasons: seasons,
            draft: draft
        )

        XCTAssertNil(outcome)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 6 })
    }

    func test_reconcileCatalog_whenRemovedFromWatched_doesNotResurrect() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 15, title: "Pruned")
        let finished = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 15, seasons: finished, draft: draft)

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        _ = try await lists.remove(itemKey: draft.itemKey, listID: watched.id)
        try await tvWatch.clearProgress(seriesID: 15)

        // Leftover freeze must not move a deleted title back to In Progress.
        var orphan = TVSeriesWatchState(seriesID: 15)
        orphan.mark(seasonNumber: 1, episodeNumber: 1)
        orphan.freezeCatalogSnapshot(from: finished)
        let store = InMemoryTVWatchStore(states: [orphan])
        let revived = TVWatchRepository(store: store, lists: lists, logger: SilentLogger())
        let grown = [season(1, episodes: 1), season(2, episodes: 4)]
        let outcome = try await revived.reconcileCatalog(
            seriesID: 15,
            seasons: grown,
            draft: draft
        )

        XCTAssertNil(outcome)
        let after = try await lists.snapshot()
        let inProgress = try XCTUnwrap(after.list(.inProgress))
        XCTAssertFalse(after.entries.contains { $0.listID == inProgress.id && $0.itemID == 15 })
    }

    func test_syncNextUp_emptyCatalog_preservesNextUp() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 21, title: "Offline")
        let seasons = [season(1, episodes: 3)]
        _ = try await tvWatch.markEpisode(
            seriesID: 21,
            seasonNumber: 1,
            episodeNumber: 1,
            title: "One",
            draft: draft,
            seasons: seasons
        )

        let beforeState = try await tvWatch.state(seriesID: 21)
        let before = try XCTUnwrap(beforeState)
        XCTAssertEqual(before.nextUp, TVEpisodeRef(seasonNumber: 1, episodeNumber: 2))

        let after = try await tvWatch.syncNextUp(seriesID: 21, seasons: [])
        XCTAssertEqual(after?.nextUp, TVEpisodeRef(seasonNumber: 1, episodeNumber: 2))
        XCTAssertEqual(after?.nextUpTitle, before.nextUpTitle)
    }

    func test_markEpisode_listPersistFailure_rollsLedgerBack() async throws {
        let store = InMemoryListsStore()
        let lists = ListsRepository(store: store, logger: SilentLogger())
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 33, title: "Rollback")
        let seasons = [season(1, episodes: 2)]
        // Warm lists cache, then fail the next persist (In Progress add).
        _ = try await lists.snapshot()
        await store.setSaveError(AppError.persistence)

        do {
            _ = try await tvWatch.markEpisode(
                seriesID: 33,
                seasonNumber: 1,
                episodeNumber: 1,
                title: "One",
                draft: draft,
                seasons: seasons
            )
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error as? AppError, .persistence)
        }
        await store.setSaveError(nil)

        let state = try await tvWatch.state(seriesID: 33)
        XCTAssertNil(state)
        let snapshot = try await lists.snapshot()
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        XCTAssertFalse(snapshot.entries.contains { $0.listID == inProgress.id && $0.itemID == 33 })
    }

    func test_clearSeries_listPersistFailure_restoresLedger() async throws {
        let store = InMemoryListsStore()
        let lists = ListsRepository(store: store, logger: SilentLogger())
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 34, title: "Keep Me")
        let seasons = [season(1, episodes: 1)]
        _ = try await tvWatch.markSeries(seriesID: 34, seasons: seasons, draft: draft)
        await store.setSaveError(AppError.persistence)

        do {
            _ = try await tvWatch.clearSeries(seriesID: 34, draft: draft)
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error as? AppError, .persistence)
        }
        await store.setSaveError(nil)

        let restoredState = try await tvWatch.state(seriesID: 34)
        let restored = try XCTUnwrap(restoredState)
        XCTAssertTrue(restored.isSeriesComplete(against: seasons))
    }

    func test_markEpisode_alwaysProvidesWatchUndo() async throws {
        let lists = makeLists()
        let tvWatch = makeTVWatch(lists: lists)
        let draft = tvDraft(id: 42, title: "Severance")
        let seasons = [season(1, episodes: 3)]
        _ = try await tvWatch.markEpisode(
            seriesID: 42,
            seasonNumber: 1,
            episodeNumber: 1,
            title: "One",
            draft: draft,
            seasons: seasons
        )
        let second = try await tvWatch.markEpisode(
            seriesID: 42,
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Two",
            draft: draft,
            seasons: seasons
        )

        XCTAssertNil(second.membershipChange)
        XCTAssertNotNil(second.watchUndo)
    }

    // MARK: - Helpers

    private func makeLists() -> ListsRepository {
        ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
    }

    private func makeTVWatch(lists: ListsRepository) -> TVWatchRepository {
        TVWatchRepository(
            store: InMemoryTVWatchStore(),
            lists: lists,
            logger: SilentLogger()
        )
    }

    private func tvDraft(id: Int, title: String) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .tv,
            title: title,
            imagePath: "/poster.jpg",
            releaseDate: nil,
            genreNames: ["Drama"],
            voteAverage: 8,
            popularity: 10
        )
    }

    private func season(_ number: Int, episodes: Int) -> TVSeasonSummary {
        TVSeasonSummary(
            id: number,
            name: "Season \(number)",
            seasonNumber: number,
            episodeCount: episodes,
            airDate: nil,
            posterPath: nil
        )
    }
}
