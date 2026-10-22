//
//  OnboardingSeenViewModelTests.swift
//  SilverScreenTests
//
//  The seen step: picks land on Watched through the real repositories, scores
//  save as half points, and suggestion sources fail independently.
//

import XCTest
@testable import SilverScreen

@MainActor
final class OnboardingSeenViewModelTests: XCTestCase {
    private var lists: ListsRepository!
    private var annotations: AnnotationsRepository!
    private var tvWatch: TVWatchRepository!

    override func setUp() {
        super.setUp()
        lists = .empty()
        annotations = .empty()
        tvWatch = TVWatchRepository(store: InMemoryTVWatchStore(), lists: lists, logger: SilentLogger())
    }

    // MARK: - Picks

    func test_toggleMovie_unrated_addsToWatched() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))

        await viewModel.toggle(title)

        XCTAssertTrue(viewModel.isPicked(title))
        let keys = try await watchedKeys()
        XCTAssertTrue(keys.contains("movie-278"))
        let saved = try await annotations.annotation(for: .movie(278))
        XCTAssertNil(saved)
    }

    func test_rateMovie_savesScoreAndStaysOnWatched() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))
        await viewModel.toggle(title)

        _ = await viewModel.rate(title, score: 8.5, note: "")

        let saved = try await annotations.annotation(for: .movie(278))
        XCTAssertEqual(saved?.score, 8.5)
        XCTAssertEqual(viewModel.score(for: title), 8.5)
        let keys = try await watchedKeys()
        XCTAssertTrue(keys.contains("movie-278"))
    }

    func test_rate_unpickedTitle_savesNothing() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))

        _ = await viewModel.rate(title, score: 6, note: "")

        let saved = try await annotations.annotation(for: .movie(278))
        XCTAssertNil(saved)
    }

    func test_rate_savesNoteWithScore() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))
        await viewModel.toggle(title)

        let result = await viewModel.rate(title, score: 7.5, note: "Rewatch with friends")

        XCTAssertEqual(result, .succeeded)
        let saved = try await annotations.annotation(for: .movie(278))
        XCTAssertEqual(saved?.note, "Rewatch with friends")
        XCTAssertEqual(viewModel.note(for: title), "Rewatch with friends")
    }

    func test_rate_unpickedTitle_fails() async {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))

        let result = await viewModel.rate(title, score: 6, note: "")

        XCTAssertEqual(result, .failed)
    }

    func test_goalMet_afterFiveRatings() async {
        let viewModel = makeViewModel()
        for id in 1...5 {
            let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: id))
            await viewModel.toggle(title)
            _ = await viewModel.rate(title, score: 8, note: "")
        }

        XCTAssertTrue(viewModel.isGoalMet)
        XCTAssertEqual(viewModel.goalText, "5 rated. Nice start.")
    }

    func test_clearRating_clearsScore() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))
        await viewModel.toggle(title)
        _ = await viewModel.rate(title, score: 4, note: "")

        _ = await viewModel.clearRating(title)

        let saved = try await annotations.annotation(for: .movie(278))
        XCTAssertNil(saved)
        XCTAssertEqual(viewModel.ratedCount, 0)
    }

    func test_toggleTwice_removesFromWatchedAndClearsScore() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))
        await viewModel.toggle(title)
        _ = await viewModel.rate(title, score: 9, note: "")

        await viewModel.toggle(title)

        XCTAssertFalse(viewModel.isPicked(title))
        let keys = try await watchedKeys()
        XCTAssertFalse(keys.contains("movie-278"))
        let saved = try await annotations.annotation(for: .movie(278))
        XCTAssertNil(saved)
    }

    func test_toggleSeries_marksEveryEpisodeAndAddsToWatched() async throws {
        let client = RoutingHTTPClient(routes: ["/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad)])
        let viewModel = makeViewModel(client: client)
        let title = OnboardingTitle(draft: OnboardingFixtures.seriesDraft(id: 1396))

        await viewModel.toggle(title)

        let keys = try await watchedKeys()

        XCTAssertTrue(keys.contains("tv-1396"))
        let completed = try await tvWatch.completedEpisodeCount(seriesID: 1396)
        XCTAssertEqual(completed, 20)
    }

    func test_rateSeries_savesSeriesScore() async throws {
        let client = RoutingHTTPClient(routes: ["/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad)])
        let viewModel = makeViewModel(client: client)
        let title = OnboardingTitle(draft: OnboardingFixtures.seriesDraft(id: 1396))
        await viewModel.toggle(title)

        _ = await viewModel.rate(title, score: 9.5, note: "")

        let saved = try await annotations.annotation(for: .series(1396))
        XCTAssertEqual(saved?.score, 9.5)
    }

    func test_toggleSeries_whenSeriesFetchFails_revertsPick() async throws {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.seriesDraft(id: 1396))

        await viewModel.toggle(title)

        XCTAssertFalse(viewModel.isPicked(title))
        let keys = try await watchedKeys()
        XCTAssertFalse(keys.contains("tv-1396"))
    }

    func test_goalText_countsRatingsTowardFive() async {
        let viewModel = makeViewModel()
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))
        await viewModel.toggle(title)
        _ = await viewModel.rate(title, score: 7, note: "")

        XCTAssertEqual(viewModel.goalText, "1 of 5 rated")
    }

    // MARK: - Suggestions

    func test_load_mixesMoviesShowsAndBestPicture() async {
        let client = RoutingHTTPClient(routes: [
            "/discover/movie": .success(TMDBFixtures.topMoviesPage1),
            "/tv/popular": .success(TMDBFixtures.popularTVPage),
            "/movie/550": .success(Self.bestPictureDetail),
        ])
        let viewModel = makeViewModel(client: client, awards: Self.bestPictureAwards())

        await viewModel.load()

        guard case .loaded(let titles, _) = viewModel.suggestions else {
            return XCTFail("Expected loaded, got \(viewModel.suggestions)")
        }
        XCTAssertEqual(titles.first?.id, "movie-550")
        XCTAssertTrue(titles.contains { $0.id == "tv-1396" })
        XCTAssertTrue(titles.contains { $0.id == "movie-278" })
    }

    func test_load_dropsSeriesWithFewRatings() async {
        let client = RoutingHTTPClient(routes: [
            "/tv/popular": .success(Self.regionalAndWidelySeenTV),
            "/discover/tv": .success(TMDBFixtures.popularTVPage),
        ])
        let viewModel = makeViewModel(client: client)

        await viewModel.load()

        guard case .loaded(let titles, _) = viewModel.suggestions else {
            return XCTFail("Expected loaded, got \(viewModel.suggestions)")
        }
        XCTAssertEqual(titles.map(\.id), ["tv-1396", "tv-1399"])
    }

    func test_load_everySourceOffline_fails() async {
        let viewModel = makeViewModel()

        await viewModel.load()

        XCTAssertEqual(viewModel.suggestions, .failed(.offline))
    }

    func test_load_restoresPicksAlreadyOnWatched() async throws {
        _ = try await lists.addToWatched(OnboardingFixtures.movieDraft(id: 278))
        try await annotations.saveScore(6.5, for: .movie(278))
        let viewModel = makeViewModel()

        await viewModel.load()

        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 278))
        XCTAssertTrue(viewModel.isPicked(title))
        XCTAssertEqual(viewModel.score(for: title), 6.5)
    }

    func test_search_mergesMoviesAndShows() async {
        let client = RoutingHTTPClient(routes: [
            "/search/movie": .success(TMDBFixtures.topMoviesPage1),
            "/search/tv": .success(TMDBFixtures.popularTVPage),
        ])
        let viewModel = makeViewModel(client: client)
        viewModel.searchText = "bad"

        await viewModel.search()

        guard case .loaded(let titles, _) = viewModel.displayed else {
            return XCTFail("Expected loaded, got \(viewModel.displayed)")
        }
        XCTAssertEqual(Set(titles.map(\.id)), ["movie-278", "movie-238", "tv-1396"])
    }

    func test_search_emptyQuery_showsSuggestions() async {
        let viewModel = makeViewModel()
        viewModel.searchText = "   "

        await viewModel.search()

        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(viewModel.searchResults, .idle)
    }

    // MARK: - Helpers

    private func makeViewModel(
        client: any HTTPClient = FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet))),
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) -> OnboardingSeenViewModel {
        OnboardingSeenViewModel(
            movies: .test(client: client),
            shows: .test(client: client),
            lists: lists,
            annotations: annotations,
            tvWatch: tvWatch,
            awards: awards
        )
    }

    private func watchedKeys() async throws -> Set<String> {
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        return Set(snapshot.entries.filter { $0.listID == watched.id }.map(\.itemKey))
    }

    /// Popular TV with a soap of 48 ratings ahead of two widely seen shows.
    private static let regionalAndWidelySeenTV = Data(
        """
        {
          "page": 1,
          "total_pages": 1,
          "results": [
            { "id": 9001, "name": "Come Home Love", "genre_ids": [35], "vote_count": 48 },
            { "id": 1396, "name": "Breaking Bad", "genre_ids": [18], "vote_count": 18900 },
            { "id": 1399, "name": "Game of Thrones", "genre_ids": [18], "vote_count": 27997 }
          ]
        }
        """.utf8
    )

    private static func bestPictureAwards() -> AwardsRepository {
        AwardsRepository(
            catalog: AwardsCatalog(
                generatedAt: Date(),
                credits: [
                    AwardCredit(
                        key: "academy|bp|2000|won|550",
                        family: .academy,
                        category: "Best Picture",
                        categoryID: "Q102427",
                        won: true,
                        year: 2000,
                        title: "Fight Club",
                        imdbID: nil,
                        wikidataID: nil,
                        work: AwardWork(kind: .movie, movieID: 550)
                    ),
                ]
            )
        )
    }

    private static let bestPictureDetail = Data(
        """
        {
          "id": 550,
          "title": "Fight Club",
          "overview": "An insomniac office worker.",
          "poster_path": "/fc.jpg",
          "release_date": "1999-10-15",
          "vote_average": 8.4,
          "popularity": 60,
          "genres": [{"id": 18, "name": "Drama"}]
        }
        """.utf8
    )
}
