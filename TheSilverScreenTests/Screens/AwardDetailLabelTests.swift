//
//  AwardDetailLabelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class AwardDetailLabelTests: XCTestCase {

    func test_movie_knownID_setsAwardLabels() async {
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: DetailAwardHTTPClient()),
            annotations: AnnotationsRepository.empty(),
            lists: .empty(),
            awards: AwardsRepository(catalog: Self.catalog)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.awardRows, [
            AwardRow(
                id: "movie-win",
                family: .academy,
                categoryLabel: "Best Picture",
                detailLine: "1995",
                accessibilityName: "Oscar for Best Picture, 1995",
                route: nil
            ),
        ])
    }

    func test_movie_unknownID_hasNoAwardLabels() async {
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: DetailAwardHTTPClient()),
            annotations: AnnotationsRepository.empty(),
            lists: .empty(),
            awards: AwardsRepository(catalog: .empty)
        )

        await viewModel.load()

        guard case .loaded = viewModel.state else {
            return XCTFail("Expected the movie to load, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.awardRows, [])
    }

    func test_series_knownID_setsAwardLabels() async {
        let client = RoutingHTTPClient(routes: [
            "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsEmpty),
            "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
        ])
        let viewModel = TVSeriesViewModel(
            seriesID: 1396,
            shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            awards: AwardsRepository(catalog: Self.catalog)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.awardRows, [
            AwardRow(
                id: "series-win",
                family: .emmy,
                categoryLabel: "Outstanding Drama Series",
                detailLine: "2014",
                accessibilityName: "Emmy for Outstanding Drama Series, 2014",
                route: nil
            ),
        ])
    }

    func test_season_knownID_setsNominationLabels() async {
        let viewModel = TVSeasonViewModel(
            seriesID: 1396,
            seriesName: "Breaking Bad",
            seasonNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvSeasonPilot))),
            annotations: AnnotationsRepository.empty(),
            awards: AwardsRepository(catalog: Self.catalog)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.awardRows, [
            AwardRow(
                id: "season-nom",
                family: .emmy,
                categoryLabel: "Outstanding Drama Series nominee",
                detailLine: "2009",
                accessibilityName: "Emmy nominee for Outstanding Drama Series, 2009",
                route: nil
            ),
        ])
    }

    func test_episode_knownID_setsAwardLabels() async {
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 5,
            episodeNumber: 14,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))),
            annotations: AnnotationsRepository.empty(),
            awards: AwardsRepository(catalog: Self.catalog)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.awardRows, [
            AwardRow(
                id: "episode-win",
                family: .emmy,
                categoryLabel: "Outstanding Writing for a Drama Series",
                detailLine: "2014",
                accessibilityName: "Emmy for Outstanding Writing for a Drama Series, 2014",
                route: nil
            ),
        ])
    }

    func test_episode_unknownID_hasNoAwardLabels() async {
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))),
            annotations: AnnotationsRepository.empty(),
            awards: AwardsRepository(catalog: Self.catalog)
        )

        await viewModel.load()

        guard case .loaded = viewModel.state else {
            return XCTFail("Expected the episode to load, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.awardRows, [])
    }

    private static let catalog = AwardsCatalog(
        generatedAt: Date(timeIntervalSince1970: 1),
        credits: [
            AwardCredit(
                key: "movie-win",
                family: .academy,
                category: "Best Picture",
                categoryID: "Q102427",
                won: true,
                year: 1995,
                title: "The Shawshank Redemption",
                imdbID: nil,
                wikidataID: nil,
                work: AwardWork(kind: .movie, movieID: 278)
            ),
            AwardCredit(
                key: "series-win",
                family: .emmy,
                category: "Outstanding Drama Series",
                categoryID: "Q989438",
                won: true,
                year: 2014,
                title: "Breaking Bad",
                imdbID: nil,
                wikidataID: nil,
                work: AwardWork(kind: .series, seriesID: 1396, seriesName: "Breaking Bad")
            ),
            AwardCredit(
                key: "season-nom",
                family: .emmy,
                category: "Outstanding Drama Series",
                categoryID: "Q989438",
                won: false,
                year: 2009,
                title: "Breaking Bad",
                imdbID: nil,
                wikidataID: nil,
                work: AwardWork(kind: .season, seriesID: 1396, seriesName: "Breaking Bad", seasonNumber: 1)
            ),
            AwardCredit(
                key: "episode-win",
                family: .emmy,
                category: "Outstanding Writing for a Drama Series",
                categoryID: "Q123",
                won: true,
                year: 2014,
                title: "Ozymandias",
                imdbID: nil,
                wikidataID: nil,
                work: AwardWork(
                    kind: .episode,
                    seriesID: 1396,
                    seriesName: "Breaking Bad",
                    seasonNumber: 5,
                    episodeNumber: 14
                )
            ),
        ]
    )
}

/// Movie JSON for the detail request, and an empty review page.
private actor DetailAwardHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path.contains("/reviews") == true {
            return try await FakeHTTPClient(stub: .success(TMDBFixtures.movieReviewsEmpty)).data(for: request)
        }
        return try await FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank)).data(for: request)
    }
}

