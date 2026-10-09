//
//  TVWatchRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

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
