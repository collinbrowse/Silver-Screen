//
//  SearchViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class SearchViewModelTests: XCTestCase {

    func test_reloadAndRefresh_stampSavedMovieScore() async throws {
        let annotations = AnnotationsRepository.empty()
        let viewModel = makeViewModel(
            routes: ["search/movie": .success(TMDBFixtures.topMoviesPage1)],
            annotations: annotations
        )
        viewModel.query = "shawshank"
        await viewModel.submit()
        try await annotations.saveScore(8, for: .movie(278))

        await viewModel.reloadDisplayedScores()

        guard case .loaded(.movies(let rows), _) = viewModel.state else {
            return XCTFail("Expected rows after returning, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.first { $0.id == 278 }?.formattedUserScore, "8.0 / 10")

        await viewModel.refresh()

        guard case .loaded(.movies(let refreshed), activity: .none) = viewModel.state else {
            return XCTFail("Expected rows after refresh, got \(viewModel.state)")
        }
        XCTAssertEqual(refreshed.first { $0.id == 278 }?.formattedUserScore, "8.0 / 10")
    }

    func test_load_emptyQuery_exposesAwardShelves() async {
        let client = RoutingHTTPClient(routes: [
            "movie/popular": .success(TMDBFixtures.topMoviesPage1),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.showsAwardShelves)
        XCTAssertFalse(viewModel.showsScopePicker)
        XCTAssertEqual(
            viewModel.shelves.map(\.title),
            ["Oscar Winners", "BAFTAs", "Emmys"]
        )
        let count = await client.requestCount
        XCTAssertEqual(count, 0)
    }

    func test_commitQueryChange_searchesMovies() async {
        let viewModel = makeViewModel(
            routes: [
                "movie/popular": .success(TMDBFixtures.topMoviesPage1),
                "search/movie": .success(TMDBFixtures.topMoviesPage2),
            ]
        )
        viewModel.query = "godfather"

        await viewModel.commitQueryChange()

        guard case .loaded(.movies(let rows), _) = viewModel.state else {
            return XCTFail("Expected search results, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.map(\.id), [240])
    }

    func test_keyboardDismissed_keepsSearchResults() async {
        let viewModel = makeViewModel(
            routes: ["search/movie": .success(TMDBFixtures.topMoviesPage2)]
        )
        viewModel.query = "godfather"
        await viewModel.commitQueryChange()
        let before = viewModel.state

        viewModel.keyboardDismissed()

        XCTAssertEqual(viewModel.state, before)
        XCTAssertEqual(viewModel.query, "godfather")
    }

    func test_scopeChange_loadsTVForTheSameQuery() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .success(TMDBFixtures.popularTVPage),
            ]
        )
        viewModel.query = "breaking"
        await viewModel.submit()
        viewModel.scope = .tv

        await viewModel.reloadForScopeChange()

        guard case .loaded(.tv(let rows), _) = viewModel.state else {
            return XCTFail("Expected TV, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.map(\.name), ["Breaking Bad"])
        XCTAssertEqual(rows[0].genreNames, ["Drama", "Crime"])
        XCTAssertEqual(rows[0].formattedFirstAirDate, "Jan 20, 2008")
    }

    func test_peopleSearch_mapsKnownForDepartment() async {
        let viewModel = makeViewModel(
            routes: ["search/person": .success(TMDBFixtures.popularPeoplePage)]
        )
        viewModel.scope = .people
        viewModel.query = "pitt"

        await viewModel.commitQueryChange()

        guard case .loaded(.people(let rows), _) = viewModel.state else {
            return XCTFail("Expected people, got \(viewModel.state)")
        }
        XCTAssertEqual(rows[0].name, "Brad Pitt")
        XCTAssertEqual(rows[0].knownForDepartment, "Acting")
        XCTAssertEqual(rows[0].profilePath, "/pitt.jpg")
    }

    func test_loadMore_appendsSecondMoviePage() async {
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.topMoviesPage1),
            .success(TMDBFixtures.topMoviesPage2),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )

        viewModel.query = "shawshank"
        await viewModel.submit()
        await viewModel.loadMore()

        guard case .loaded(.movies(let rows), activity: .none) = viewModel.state else {
            return XCTFail("Expected paged movies, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.map(\.id), [278, 238, 240])
    }

    func test_submit_oneCharacterReplacesThePopularList() async {
        let client = RoutingHTTPClient(routes: [
            "movie/popular": .success(TMDBFixtures.topMoviesPage1),
            "search/movie": .success(TMDBFixtures.topMoviesPage2),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.showsAwardShelves)
        viewModel.query = "a"

        await viewModel.submit()

        guard case .loaded(.movies(let rows), _) = viewModel.state else {
            return XCTFail("Expected search results, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.map(\.id), [240])
        let searchCount = await client.requests.filter { $0.url?.path.contains("search/movie") == true }.count
        XCTAssertEqual(searchCount, 1)
    }

    func test_scopeChange_reusesTheSegmentCache() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage1),
            "search/tv": .success(TMDBFixtures.popularTVPage),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "shawshank"
        await viewModel.submit()
        viewModel.scope = .tv
        await viewModel.reloadForScopeChange()
        viewModel.scope = .movies
        await viewModel.reloadForScopeChange()

        let count = await client.requestCount
        XCTAssertEqual(count, 2)
        guard case .loaded(.movies(let rows), _) = viewModel.state else {
            return XCTFail("Expected the cached movie list")
        }
        XCTAssertEqual(rows.map(\.id), [278, 238])
        XCTAssertEqual(viewModel.query, "shawshank")
    }

    func test_emptyQuery_doesNotRefetchPopular() async {
        let client = RoutingHTTPClient(routes: [
            "movie/popular": .success(TMDBFixtures.topMoviesPage1),
            "search/movie": .success(TMDBFixtures.topMoviesPage2),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        await viewModel.load()
        viewModel.query = "godfather"
        await viewModel.submit()
        viewModel.query = "  "
        await viewModel.submit()

        let popularCount = await client.requests.filter { $0.url?.path.contains("movie/popular") == true }.count
        let searchCount = await client.requests.filter { $0.url?.path.contains("search/movie") == true }.count
        XCTAssertEqual(popularCount, 0)
        XCTAssertEqual(searchCount, 1)
        XCTAssertTrue(viewModel.showsAwardShelves)
        XCTAssertFalse(viewModel.showsScopePicker)
    }

    func test_submit_whileTheFieldIsFocusedAndEmpty_keepsThePlaceholder() async {
        let client = RoutingHTTPClient(routes: [
            "movie/popular": .success(TMDBFixtures.topMoviesPage1),
            "search/movie": .success(TMDBFixtures.topMoviesPage2),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        await viewModel.load()
        viewModel.query = "godfather"
        await viewModel.submit()
        viewModel.setFieldFocused(true)
        viewModel.query = ""
        await viewModel.submit()

        XCTAssertTrue(viewModel.showsFocusedPlaceholder)
        XCTAssertEqual(viewModel.state, .empty)

        viewModel.restoreAfterDismiss()

        XCTAssertTrue(viewModel.showsAwardShelves)
        XCTAssertFalse(viewModel.showsFocusedPlaceholder)
        XCTAssertEqual(viewModel.query, "")
    }

    func test_focusedEmptyField_restoresTheLastResults() async {
        let viewModel = makeViewModel(
            routes: ["movie/popular": .success(TMDBFixtures.topMoviesPage1)]
        )
        await viewModel.load()
        let loaded = viewModel.state

        viewModel.setFieldFocused(true)

        XCTAssertTrue(viewModel.showsFocusedPlaceholder)
        XCTAssertEqual(viewModel.state, .empty)

        viewModel.restoreAfterDismiss()

        XCTAssertFalse(viewModel.showsFocusedPlaceholder)
        XCTAssertTrue(viewModel.showsAwardShelves)
        XCTAssertEqual(viewModel.state, loaded)
        XCTAssertEqual(viewModel.query, "")
    }

    func test_search_sendsIncludeAdultFalse() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.popularTVPage))
        let shows = TVRepository.test(client: client)
        _ = try await shows.search(query: "bad", page: 1, locale: Locale(identifier: "en"))
        let tvItems = await queryItems(client)
        XCTAssertTrue(tvItems.contains(URLQueryItem(name: "include_adult", value: "false")))
        XCTAssertFalse(tvItems.contains { $0.name == "region" })

        let peopleClient = RecordingHTTPClient(stub: .success(TMDBFixtures.popularPeoplePage))
        let people = PersonRepository.test(client: peopleClient)
        _ = try await people.search(query: "pitt", page: 1, locale: Locale(identifier: "en_US"))
        let personItems = await queryItems(peopleClient)
        XCTAssertTrue(personItems.contains(URLQueryItem(name: "include_adult", value: "false")))
        XCTAssertTrue(personItems.contains(URLQueryItem(name: "language", value: "en-US")))
        XCTAssertTrue(personItems.contains(URLQueryItem(name: "region", value: "US")))
    }

    func test_search_ordersNameMatchesByPopularity() async {
        let payload = Data("""
        {
          "page": 1,
          "results": [
            {"id": 1, "title": "SPI", "genre_ids": [99], "vote_average": 5.0, "popularity": 1.0, "release_date": "2020-01-01"},
            {"id": 2, "title": "Spider-Man: Brand New Day", "genre_ids": [28], "vote_average": 8.0, "popularity": 100.0, "release_date": "2026-07-29"}
          ],
          "total_pages": 1
        }
        """.utf8)
        let viewModel = makeViewModel(routes: ["search/movie": .success(payload)])
        viewModel.query = "Spi"
        await viewModel.submit()
        guard case .loaded(.movies(let rows), _) = viewModel.state else {
            return XCTFail("Expected movies, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.map(\.title), ["Spider-Man: Brand New Day", "SPI"])
    }

    func test_search_genreUsesDiscoverSortedByPopularity() async throws {
        let client = RoutingHTTPClient(routes: [
            "discover/movie": .success(TMDBFixtures.topMoviesPage1),
            "discover/tv": .success(TMDBFixtures.popularTVPage),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "Horror"
        await viewModel.submit()
        let movieURL = await client.requests.last?.url
        let movieItems = URLComponents(url: movieURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(movieURL?.path, "/3/discover/movie")
        XCTAssertTrue(movieItems.contains(URLQueryItem(name: "with_genres", value: "27")))
        XCTAssertTrue(movieItems.contains(URLQueryItem(name: "sort_by", value: "popularity.desc")))

        viewModel.scope = .tv
        viewModel.query = "Drama"
        await viewModel.submit()
        let tvURL = await client.requests.last?.url
        let tvItems = URLComponents(url: tvURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(tvURL?.path, "/3/discover/tv")
        XCTAssertTrue(tvItems.contains(URLQueryItem(name: "with_genres", value: "18")))
    }

    func test_focusedPlaceholder_asksForANameOrGenre() {
        let viewModel = makeViewModel(routes: [:])
        viewModel.setFieldFocused(true)
        XCTAssertEqual(viewModel.emptyMessage, "Type a name or genre")
    }

    private func queryItems(_ client: RecordingHTTPClient) async -> [URLQueryItem] {
        let url = await client.lastURL
        return URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func makeViewModel(
        routes: [String: FakeHTTPClient.Stub],
        annotations: AnnotationsRepository = .empty()
    ) -> SearchViewModel {
        let client = RoutingHTTPClient(routes: routes)
        return SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: annotations,
            sleeper: NoopSleeper()
        )
    }
}
