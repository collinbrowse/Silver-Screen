//
//  GenreBrowseViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class GenreBrowseViewModelTests: XCTestCase {

    private let locale = Locale(identifier: "en_US")
    private let today = TestMovies.date("2024-06-15")
    private let genre = MergedGenre.drama

    func test_load_all_fetchesBothDiscoverPathsWithGenreIds() async throws {
        let client = RoutingHTTPClient(routes: [
            "discover/movie": .success(TMDBFixtures.topMoviesPage1),
            "discover/tv": .success(tvPage),
        ])
        let viewModel = makeViewModel(client: client)

        await viewModel.load()

        let paths = await client.requests.compactMap { $0.url?.path }
        XCTAssertTrue(paths.contains("/3/discover/movie"))
        XCTAssertTrue(paths.contains("/3/discover/tv"))
        let movieItems = queryItems(from: await client.requests.first { $0.url?.path.contains("discover/movie") == true }!)
        XCTAssertTrue(movieItems.contains(URLQueryItem(name: "with_genres", value: "18")))
        let tvItems = queryItems(from: await client.requests.first { $0.url?.path.contains("discover/tv") == true }!)
        XCTAssertTrue(tvItems.contains(URLQueryItem(name: "with_genres", value: "18")))
        if case .loaded(let rows, _) = viewModel.state {
            XCTAssertFalse(rows.isEmpty)
        } else {
            XCTFail("Expected loaded state")
        }
    }

    func test_setMedia_movies_doesNotCallTV() async {
        let client = RoutingHTTPClient(routes: [
            "discover/movie": .success(TMDBFixtures.topMoviesPage1),
            "discover/tv": .success(tvPage),
        ])
        let viewModel = makeViewModel(client: client)

        await viewModel.load()
        await viewModel.setMedia(.movies)

        let paths = await client.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths.filter { $0.contains("discover/tv") }.count, 1)
    }

    func test_setSort_topRated_sendsVoteAverageAndFloor() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let movies = MovieRepository.test(client: client)
        let shows = TVRepository.test(client: RecordingHTTPClient(stub: .success(tvPage)))
        let day = today
        let viewModel = GenreBrowseViewModel(
            genre: genre,
            movies: movies,
            shows: shows,
            annotations: .empty(),
            locale: locale,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            today: { day }
        )

        await viewModel.load()
        await viewModel.setMedia(.movies)
        await viewModel.setSort(.topRated)

        let items = await queryItems(client)
        XCTAssertTrue(items.contains(URLQueryItem(name: "sort_by", value: "vote_average.desc")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "vote_count.gte", value: "50")))
    }

    func test_load_whenOffline_setsFailedState() async {
        let client = FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
        let viewModel = makeViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    private func makeViewModel(client: any HTTPClient) -> GenreBrowseViewModel {
        let day = today
        return GenreBrowseViewModel(
            genre: genre,
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            annotations: .empty(),
            locale: locale,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            today: { day }
        )
    }

    private func queryItems(from request: URLRequest) -> [URLQueryItem] {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func queryItems(_ client: RecordingHTTPClient) async -> [URLQueryItem] {
        let url = await client.lastURL
        return URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private var tvPage: Data {
        Data(
            """
            {
              "page": 1,
              "results": [
                {
                  "id": 11, "name": "Middlemarch", "genre_ids": [18],
                  "first_air_date": "1994-01-01", "vote_average": 9.1
                }
              ],
              "total_pages": 1,
              "total_results": 1
            }
            """.utf8
        )
    }
}
