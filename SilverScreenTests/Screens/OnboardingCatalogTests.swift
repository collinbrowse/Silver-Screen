//
//  OnboardingCatalogTests.swift
//  SilverScreenTests
//
//  Grid merging, exclusion, the star mapping, and width-based columns.
//

import SwiftUI
import XCTest
@testable import SilverScreen

@MainActor
final class OnboardingCatalogTests: XCTestCase {
    func test_interleave_alternatesSourcesAndDropsDuplicates() {
        let movies = [movie(1), movie(2)]
        let shows = [series(1), movie(1), series(2)]

        let merged = OnboardingCatalog.interleave([movies, shows])

        XCTAssertEqual(merged.map(\.id), ["movie-1", "tv-1", "movie-2", "tv-2"])
    }

    func test_interleave_stopsAtLimit() {
        let merged = OnboardingCatalog.interleave([[movie(1), movie(2), movie(3)]], limit: 2)

        XCTAssertEqual(merged.count, 2)
    }

    func test_excluding_dropsPickedKeys() {
        let kept = OnboardingCatalog.excluding([movie(1), series(1)], keys: ["movie-1"])

        XCTAssertEqual(kept.map(\.id), ["tv-1"])
    }

    func test_sourceResults_oneFailure_keepsOtherSources() {
        var results = OnboardingSourceResults()
        results.append(.failure(AppError.offline))
        results.append(.success([movie(1)]))

        XCTAssertEqual(results.state(), .loaded([movie(1)]))
    }

    func test_sourceResults_noTitles_isEmpty() {
        var results = OnboardingSourceResults()
        results.append(.success([]))

        XCTAssertEqual(results.state(), .empty)
    }

    func test_released_dropsFutureAndUndatedMovies() {
        let today = TestMovies.date("2026-10-16")
        let movies = [
            TestMovies.make(id: 1, releaseDate: TestMovies.date("2026-10-16")),
            TestMovies.make(id: 2, releaseDate: TestMovies.date("2026-12-18")),
            TestMovies.make(id: 3, releaseDate: nil),
        ]

        XCTAssertEqual(OnboardingCatalog.released(movies, by: today).map(\.id), [1])
    }

    func test_seriesDropping_removesTalkAndNews() {
        let shows = [
            TVSeriesSummary(id: 1, name: "Drama", posterPath: nil, firstAirDate: nil, genreIDs: [18]),
            TVSeriesSummary(id: 2, name: "Late Night", posterPath: nil, firstAirDate: nil, genreIDs: [35, 10767]),
        ]

        let kept = OnboardingCatalog.series(shows, dropping: OnboardingCatalog.dailyTVGenres)

        XCTAssertEqual(kept.map(\.id), [1])
    }

    func test_starScore_mapsTouchToHalfPoints() {
        XCTAssertEqual(OnboardingStarRating.score(at: 0, width: 100), 0.5)
        XCTAssertEqual(OnboardingStarRating.score(at: 50, width: 100), 5)
        XCTAssertEqual(OnboardingStarRating.score(at: 51, width: 100), 5.5)
        XCTAssertEqual(OnboardingStarRating.score(at: 140, width: 100), 10)
    }

    func test_gridLayout_columnsFollowAvailableWidth() {
        let phone = OnboardingPosterGrid<EmptyView>.layout(availableWidth: 361, minimumPosterWidth: 104, spacing: 12)
        let wide = OnboardingPosterGrid<EmptyView>.layout(availableWidth: 800, minimumPosterWidth: 104, spacing: 12)

        XCTAssertEqual(phone.columns, 3)
        XCTAssertEqual(wide.columns, 7)
        XCTAssertGreaterThanOrEqual(phone.width, 104)
    }

    func test_gridLayout_narrowWidth_keepsTwoColumns() {
        let layout = OnboardingPosterGrid<EmptyView>.layout(availableWidth: 180, minimumPosterWidth: 150, spacing: 12)

        XCTAssertEqual(layout.columns, 2)
    }

    private func movie(_ id: Int) -> OnboardingTitle {
        OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: id))
    }

    private func series(_ id: Int) -> OnboardingTitle {
        OnboardingTitle(draft: OnboardingFixtures.seriesDraft(id: id))
    }
}
