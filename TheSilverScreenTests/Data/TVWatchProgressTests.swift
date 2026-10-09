//
//  TVWatchProgressTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class TVWatchProgressTests: XCTestCase {
    func test_lastCompleted_ignoresGapsBehindHighestEpisode() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.mark(seasonNumber: 1, episodeNumber: 1, title: "Pilot")
        state.mark(seasonNumber: 2, episodeNumber: 5, title: "Later")

        XCTAssertEqual(state.lastCompleted, TVEpisodeRef(seasonNumber: 2, episodeNumber: 5))
    }

    func test_progressSubtitle_showsNextEpisode() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.mark(seasonNumber: 1, episodeNumber: 2, title: "Two")
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 4,
                airDate: nil,
                posterPath: nil
            ),
        ]
        state.refreshNextUp(
            against: seasons,
            episodeTitles: [
                TVEpisodeRef(seasonNumber: 1, episodeNumber: 3): "Three",
            ]
        )

        XCTAssertEqual(state.progressSubtitle, "Next up: S1 · E3 · Three")
    }

    func test_nextEpisode_advancesToNextSeasonAfterFinale() {
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
            TVSeasonSummary(
                id: 2,
                name: "Season 2",
                seasonNumber: 2,
                episodeCount: 8,
                airDate: nil,
                posterPath: nil
            ),
        ]
        let next = TVSeriesWatchState.nextEpisode(
            after: TVEpisodeRef(seasonNumber: 1, episodeNumber: 2),
            seasons: seasons
        )

        XCTAssertEqual(next, TVEpisodeRef(seasonNumber: 2, episodeNumber: 1))
    }

    func test_refreshNextUp_whenFinaleWatchedWithGaps_usesFirstUnwatched() {
        var state = TVSeriesWatchState(seriesID: 1)
        // Watched the series finale but skipped earlier episodes.
        state.mark(seasonNumber: 1, episodeNumber: 3, title: "Finale")
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 3,
                airDate: nil,
                posterPath: nil
            ),
        ]
        state.refreshNextUp(
            against: seasons,
            episodeTitles: [
                TVEpisodeRef(seasonNumber: 1, episodeNumber: 1): "Pilot",
            ]
        )

        XCTAssertEqual(state.nextUp, TVEpisodeRef(seasonNumber: 1, episodeNumber: 1))
        XCTAssertEqual(state.progressSubtitle, "Next up: S1 · E1 · Pilot")
        XCTAssertFalse(state.isSeriesComplete(against: seasons))
    }

    func test_refreshNextUp_whenSeriesComplete_hasNoNextUp() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.markSeason(seasonNumber: 1, episodeCount: 2)
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
        ]
        state.refreshNextUp(against: seasons)

        XCTAssertNil(state.nextUp)
        XCTAssertNil(state.progressSubtitle)
    }

    func test_isSeasonComplete_requiresEveryEpisode() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.mark(seasonNumber: 1, episodeNumber: 1, title: "One")
        state.mark(seasonNumber: 1, episodeNumber: 2, title: "Two")

        XCTAssertFalse(state.isSeasonComplete(seasonNumber: 1, episodeCount: 3))
        state.mark(seasonNumber: 1, episodeNumber: 3, title: "Three")
        XCTAssertTrue(state.isSeasonComplete(seasonNumber: 1, episodeCount: 3))
    }

    func test_isSeriesComplete_ignoresSpecials() {
        let seasons = [
            TVSeasonSummary(
                id: 10,
                name: "Specials",
                seasonNumber: 0,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
            TVSeasonSummary(
                id: 11,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
        ]
        var state = TVSeriesWatchState(seriesID: 1)
        state.markSeason(seasonNumber: 1, episodeCount: 2)

        XCTAssertTrue(state.isSeriesComplete(against: seasons))
    }

    func test_hasNewCatalogContent_detectsNewSeasonWithEpisodes() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.markSeason(seasonNumber: 1, episodeCount: 2)
        state.freezeCatalogSnapshot(from: [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
        ])

        let grown = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
            TVSeasonSummary(
                id: 2,
                name: "Season 2",
                seasonNumber: 2,
                episodeCount: 8,
                airDate: nil,
                posterPath: nil
            ),
        ]
        XCTAssertTrue(state.hasNewCatalogContent(against: grown))
    }

    func test_hasNewCatalogContent_ignoresZeroEpisodeStub() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.freezeCatalogSnapshot(from: [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
        ])

        let stub = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
            TVSeasonSummary(
                id: 2,
                name: "Season 2",
                seasonNumber: 2,
                episodeCount: 0,
                airDate: nil,
                posterPath: nil
            ),
        ]
        XCTAssertFalse(state.hasNewCatalogContent(against: stub))
    }

    func test_markIgnoresSpecials() {
        var state = TVSeriesWatchState(seriesID: 1)
        XCTAssertFalse(state.mark(seasonNumber: 0, episodeNumber: 1, title: "Special"))
        XCTAssertTrue(state.completed.isEmpty)
    }

    func test_unmarkSeason_clearsOnlyThatSeason() {
        var state = TVSeriesWatchState(seriesID: 1)
        state.markSeason(seasonNumber: 1, episodeCount: 2)
        state.markSeason(seasonNumber: 2, episodeCount: 2)

        XCTAssertEqual(state.unmarkSeason(seasonNumber: 1, episodeCount: 2), 2)
        XCTAssertFalse(state.contains(seasonNumber: 1, episodeNumber: 1))
        XCTAssertTrue(state.contains(seasonNumber: 2, episodeNumber: 1))
    }

    func test_decode_normalizesSpecialsAndDuplicates() throws {
        let json = """
        {
          "seriesID": 9,
          "completed": [
            {"seasonNumber": 0, "episodeNumber": 1},
            {"seasonNumber": 1, "episodeNumber": 2},
            {"seasonNumber": 1, "episodeNumber": 2},
            {"seasonNumber": 1, "episodeNumber": 1}
          ]
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(TVSeriesWatchState.self, from: json)

        XCTAssertEqual(
            state.completed,
            [
                TVEpisodeRef(seasonNumber: 1, episodeNumber: 1),
                TVEpisodeRef(seasonNumber: 1, episodeNumber: 2),
            ]
        )
    }
}
