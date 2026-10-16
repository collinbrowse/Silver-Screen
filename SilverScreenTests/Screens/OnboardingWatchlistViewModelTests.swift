//
//  OnboardingWatchlistViewModelTests.swift
//  SilverScreenTests
//
//  The watchlist step leaves out every seen pick, and taps save to Watchlist.
//

import XCTest
@testable import SilverScreen

@MainActor
final class OnboardingWatchlistViewModelTests: XCTestCase {
    func test_load_excludesSeenPicks() async {
        let viewModel = makeViewModel(lists: .empty())

        await viewModel.load(excluding: ["movie-278"])

        XCTAssertEqual(ids(viewModel.state), ["movie-238", "tv-1396"])
    }

    func test_load_excludesTitlesAlreadyOnWatched() async throws {
        let lists = ListsRepository.empty()
        _ = try await lists.addToWatched(OnboardingFixtures.movieDraft(id: 238))
        let viewModel = makeViewModel(lists: lists)

        await viewModel.load(excluding: [])

        XCTAssertFalse(ids(viewModel.state).contains("movie-238"))
        XCTAssertTrue(ids(viewModel.state).contains("movie-278"))
    }

    func test_loadAgain_withNewSeenPicks_refilters() async {
        let viewModel = makeViewModel(lists: .empty())
        await viewModel.load(excluding: [])

        await viewModel.load(excluding: ["tv-1396"])

        XCTAssertFalse(ids(viewModel.state).contains("tv-1396"))
    }

    func test_load_everySourceOffline_failsWithoutBlocking() async {
        let client = FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
        let viewModel = OnboardingWatchlistViewModel(
            movies: .test(client: client),
            shows: .test(client: client),
            lists: .empty()
        )

        await viewModel.load(excluding: [])

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_toggle_addsToWatchlist() async throws {
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(lists: lists)
        let title = OnboardingTitle(draft: OnboardingFixtures.movieDraft(id: 238))

        await viewModel.toggle(title)

        XCTAssertTrue(viewModel.isPicked(title))
        let keys = try await watchlistKeys(lists)
        XCTAssertTrue(keys.contains("movie-238"))
    }

    func test_toggleTwice_removesFromWatchlist() async throws {
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(lists: lists)
        let title = OnboardingTitle(draft: OnboardingFixtures.seriesDraft(id: 1396))
        await viewModel.toggle(title)

        await viewModel.toggle(title)

        XCTAssertFalse(viewModel.isPicked(title))
        let keys = try await watchlistKeys(lists)
        XCTAssertFalse(keys.contains("tv-1396"))
    }

    func test_search_leavesOutSeenPicks() async {
        let client = RoutingHTTPClient(routes: [
            "/search/movie": .success(TMDBFixtures.topMoviesPage1),
            "/search/tv": .success(TMDBFixtures.popularTVPage),
            "/movie/": .success(TMDBFixtures.topMoviesPage1),
            "/tv/": .success(TMDBFixtures.popularTVPage),
        ])
        let viewModel = OnboardingWatchlistViewModel(
            movies: .test(client: client),
            shows: .test(client: client),
            lists: .empty()
        )
        await viewModel.load(excluding: ["movie-278"])
        viewModel.searchText = "the"

        await viewModel.search()

        XCTAssertEqual(Set(ids(viewModel.displayed)), ["movie-238", "tv-1396"])
    }

    private func makeViewModel(lists: ListsRepository) -> OnboardingWatchlistViewModel {
        // Every movie list returns the same two movies; every TV list returns Breaking Bad.
        let client = RoutingHTTPClient(routes: [
            "/movie/": .success(TMDBFixtures.topMoviesPage1),
            "/tv/": .success(TMDBFixtures.popularTVPage),
            "/discover/tv": .success(TMDBFixtures.popularTVPage),
        ])
        return OnboardingWatchlistViewModel(
            movies: .test(client: client),
            shows: .test(client: client),
            lists: lists
        )
    }

    private func ids(_ state: LoadState<[OnboardingTitle]>) -> [String] {
        guard case .loaded(let titles, _) = state else { return [] }
        return titles.map(\.id)
    }

    private func watchlistKeys(_ lists: ListsRepository) async throws -> Set<String> {
        let snapshot = try await lists.snapshot()
        let watchlist = try XCTUnwrap(snapshot.list(.watchlist))
        return Set(snapshot.entries.filter { $0.listID == watchlist.id }.map(\.itemKey))
    }
}
