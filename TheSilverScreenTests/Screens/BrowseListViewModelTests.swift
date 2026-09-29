//
//  BrowseListViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class BrowseListViewModelTests: XCTestCase {

    private let locale = Locale(identifier: "en_US")
    private let today = TestMovies.date("2024-06-15")

    func test_discoverMovies_topRated_sendsSortVoteCountAndLocale() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let repository = MovieRepository.test(client: client)

        _ = try await repository.discover(
            sort: .topRated,
            window: .all,
            page: 2,
            locale: locale,
            today: today
        )

        let items = await queryItems(client)
        let path = await client.lastPath
        XCTAssertEqual(path, "/3/discover/movie")
        XCTAssertTrue(items.contains(URLQueryItem(name: "sort_by", value: "vote_average.desc")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "vote_count.gte", value: "50")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "language", value: "en-US")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "region", value: "US")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "page", value: "2")))
        XCTAssertFalse(items.contains { $0.name == "primary_release_date.gte" })
    }

    func test_discoverMovies_popular_sortsByPopularityWithoutAVoteFloor() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let repository = MovieRepository.test(client: client)

        _ = try await repository.discover(
            sort: .popular,
            window: .all,
            page: 1,
            locale: locale,
            today: today
        )

        let items = await queryItems(client)
        XCTAssertTrue(items.contains(URLQueryItem(name: "sort_by", value: "popularity.desc")))
        XCTAssertFalse(items.contains { $0.name == "vote_count.gte" })
    }

    func test_mediaChange_keepsWindowAndSort() async {
        let client = RoutingHTTPClient(routes: [
            "movie/popular": .success(TMDBFixtures.topMoviesPage1),
            "discover/movie": .success(TMDBFixtures.topMoviesPage1),
            "discover/tv": .success(Self.tvPage),
            ])
        let viewModel = makeViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client)
        )

        await viewModel.load()
        await viewModel.setSort(.topRated)
        await viewModel.setMedia(.tv)
        await viewModel.setMedia(.all)

        let paths = await client.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths.first, "/3/movie/popular")
        XCTAssertEqual(paths.dropFirst().prefix(1).first, "/3/discover/movie")
        XCTAssertTrue(paths.contains("/3/discover/tv"))
        XCTAssertEqual(viewModel.sort, .topRated)
        XCTAssertEqual(viewModel.window, .all)
    }

    func test_merge_popularAlternatesMovieThenShow() {
        var merge = BrowseMerge()
        merge.appendMovies([
            candidate(.movie, id: 1, title: "Alpha", popularity: 1),
            candidate(.movie, id: 2, title: "Beta", popularity: 1),
            ])
        merge.appendShows([
            candidate(.tv, id: 3, title: "Zebra", popularity: 100),
            ])
        merge.consume(sort: .popular, moviesHaveMore: false, showsHaveMore: false)
        XCTAssertEqual(merge.shown.map(\.title), ["Alpha", "Zebra", "Beta"])
    }

    func test_discoverMovies_omitsRegionWhenLocaleHasNone() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let repository = MovieRepository.test(client: client)

        _ = try await repository.discover(
            sort: .alphabetical,
            window: .all,
            page: 1,
            locale: Locale(identifier: "en"),
            today: today
        )

        let items = await queryItems(client)
        XCTAssertTrue(items.contains(URLQueryItem(name: "sort_by", value: "title.asc")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "language", value: "en")))
        XCTAssertFalse(items.contains { $0.name == "region" })
        XCTAssertFalse(items.contains { $0.name == "vote_count.gte" })
    }

    func test_nowPlayingAndUpcoming_useTheatricalLists() async throws {
        let client = RecordingHTTPClient(stub: .success(Self.emptyPage))
        let movies = MovieRepository.test(client: client)
        let shows = TVRepository.test(client: client)
        let utc = TimeZone(secondsFromGMT: 0)!

        _ = try await movies.nowPlaying(page: 1, locale: locale)
        var path = await client.lastPath
        XCTAssertEqual(path, "/3/movie/now_playing")

        _ = try await movies.upcoming(page: 1, locale: locale)
        path = await client.lastPath
        XCTAssertEqual(path, "/3/movie/upcoming")

        _ = try await shows.onTheAir(page: 1, locale: locale)
        path = await client.lastPath
        XCTAssertEqual(path, "/3/tv/on_the_air")

        _ = try await shows.upcoming(page: 1, locale: locale, today: today, timeZone: utc)
        let items = await queryItems(client)
        path = await client.lastPath
        XCTAssertEqual(path, "/3/discover/tv")
        XCTAssertTrue(items.contains(URLQueryItem(name: "sort_by", value: "first_air_date.asc")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "first_air_date.gte", value: "2024-06-16")))

        let viewModel = makeViewModel(movies: movies, shows: shows)
        await viewModel.setWindow(.upcoming)
        XCTAssertEqual(viewModel.state, .empty)
    }

    func test_load_dropsUnknownGenreIDs() async {
        let viewModel = makeViewModel(movieStub: .success(Self.unknownGenrePage))

        await viewModel.load()

        guard case .loaded(let rows, _) = viewModel.state else {
            return XCTFail("Expected loaded rows")
        }
        XCTAssertEqual(rows.map(\.title), ["Known", "Unknown Only"])
        XCTAssertEqual(rows[0].genreNames, ["Drama"])
        XCTAssertTrue(rows[1].genreNames.isEmpty)
    }

    func test_noteListSaveFailed_setsPersistenceActivity() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.noteListSaveFailed()
        guard case .loaded(_, activity: .failed(let error)) = viewModel.state else {
            return XCTFail("Expected loaded rows with a persistence failure, got \(viewModel.state)")
        }
        XCTAssertEqual(error, .persistence)
    }

    func test_displayDate_usesDeviceLocale() {
        XCTAssertEqual(
            DisplayDate.day(TestMovies.date("2024-06-15"), locale: Locale(identifier: "en_US")),
            "Jun 15, 2024"
        )
    }

    func test_merge_nilDateIsOlder_andEqualKeysBreakAlphabeticallyThenByID() {
        let dated = candidate(.movie, id: 1, title: "Dated", date: "2020-01-01")
        let undated = candidate(.tv, id: 2, title: "Undated", date: nil)
        var merge = BrowseMerge()
        merge.appendMovies([dated])
        merge.appendShows([undated])
        merge.consume(sort: .newest, moviesHaveMore: false, showsHaveMore: false)
        XCTAssertEqual(merge.shown.map(\.title), ["Dated", "Undated"])

        merge = BrowseMerge()
        merge.appendMovies([dated])
        merge.appendShows([undated])
        merge.consume(sort: .oldest, moviesHaveMore: false, showsHaveMore: false)
        XCTAssertEqual(merge.shown.map(\.title), ["Undated", "Dated"])

        let laterID = candidate(.movie, id: 9, title: "Same", vote: 8)
        let earlierID = candidate(.tv, id: 2, title: "Same", vote: 8)
        merge = BrowseMerge()
        merge.appendMovies([laterID])
        merge.appendShows([earlierID])
        merge.consume(sort: .topRated, moviesHaveMore: false, showsHaveMore: false)
        XCTAssertEqual(merge.shown.map(\.id), [2, 9])
    }

    func test_merge_appendsWithoutReshufflingShownRows() {
        let shownMovie = candidate(.movie, id: 1, title: "Shown", vote: 8)
        let shownShow = candidate(.tv, id: 2, title: "Shown Show", vote: 7)
        let lateFavorite = candidate(.movie, id: 3, title: "Late", vote: 10)
        var merge = BrowseMerge()
        merge.appendMovies([shownMovie])
        merge.appendShows([shownShow])
        merge.consume(sort: .topRated, moviesHaveMore: true, showsHaveMore: false)
        XCTAssertEqual(merge.shown.map(\.title), ["Shown"])

        merge.appendMovies([lateFavorite])
        merge.consume(sort: .topRated, moviesHaveMore: false, showsHaveMore: false)
        XCTAssertEqual(merge.shown.map(\.title), ["Shown", "Late", "Shown Show"])
    }

    func test_all_mergesMovieAndTVPages() async {
        let client = RoutingHTTPClient(routes: [
            "discover/movie": .success(TMDBFixtures.topMoviesPage1),
            "discover/tv": .success(Self.tvPage),
            ])
        let viewModel = makeViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client)
        )
        await viewModel.setMedia(.all)
        await viewModel.setSort(.topRated)

        guard case .loaded(let rows, _) = viewModel.state else {
            return XCTFail("Expected a merged list")
        }
        XCTAssertEqual(
            rows.map(\.title),
            ["Middlemarch", "Alpha", "The Shawshank Redemption", "The Godfather"]
        )
        XCTAssertEqual(rows.map(\.identity), ["tv-11", "tv-10", "movie-278", "movie-238"])
    }

    func test_loadMore_ignoredWhileOneIsInFlight() async {
        let client = PausingHTTPClient(pauseOn: 2, pages: [
            1: TMDBFixtures.topMoviesPage1,
            2: TMDBFixtures.topMoviesPage2,
            ])
        let viewModel = makeViewModel(movies: MovieRepository.test(client: client), shows: TVRepository.test(client: client))
        await viewModel.load()

        let first = Task { await viewModel.loadMore() }
        await client.waitUntilPaused()
        await viewModel.loadMore()
        await client.release()
        await first.value

        let count = await client.requestCount
        XCTAssertEqual(count, 2)
        guard case .loaded(let rows, let activity) = viewModel.state else {
            return XCTFail("Expected loaded rows")
        }
        XCTAssertEqual(activity, .none)
        XCTAssertEqual(rows.map(\.mediaID), [278, 238, 240])
    }

    func test_loadMore_dropsDuplicateIDs() async {
        let duplicate = Self.moviePage(id: 278, title: "The Shawshank Redemption", page: 2, totalPages: 3)
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.topMoviesPage1),
            .success(duplicate),
            ])
        let viewModel = makeViewModel(movies: MovieRepository.test(client: client), shows: TVRepository.test(client: client))
        await viewModel.load()
        await viewModel.loadMore()

        guard case .loaded(let rows, _) = viewModel.state else {
            return XCTFail("Expected loaded rows")
        }
        XCTAssertEqual(rows.map(\.mediaID), [278, 238])
        XCTAssertFalse(viewModel.hasMore)
    }

    func test_changingSort_discardsThePageAlreadyInFlight() async {
        let client = PausingHTTPClient(pauseOn: 2, pages: [
            1: TMDBFixtures.topMoviesPage1,
            2: Self.moviePage(id: 1, title: "Late", page: 2, totalPages: 2),
            3: Self.moviePage(id: 2, title: "Fresh", page: 1, totalPages: 1),
            ])
        let viewModel = makeViewModel(movies: MovieRepository.test(client: client), shows: TVRepository.test(client: client))
        await viewModel.load()

        let more = Task { await viewModel.loadMore() }
        await client.waitUntilPaused()
        await viewModel.setSort(.alphabetical)
        await client.release()
        await more.value

        guard case .loaded(let rows, _) = viewModel.state else {
            return XCTFail("Expected the new sort's page")
        }
        XCTAssertEqual(rows.map(\.title), ["Fresh"])
        XCTAssertEqual(viewModel.sort, .alphabetical)
    }

    func test_refresh_whenOffline_keepsLoadedRows() async {
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.topMoviesPage1),
            .failure(URLError(.notConnectedToInternet)),
            ])
        let viewModel = makeViewModel(movies: MovieRepository.test(client: client), shows: TVRepository.test(client: client))
        await viewModel.load()
        await viewModel.refresh()

        guard case .loaded(let rows, let activity) = viewModel.state else {
            return XCTFail("Expected the first page to stay up")
        }
        XCTAssertEqual(rows.map(\.mediaID), [278, 238])
        XCTAssertEqual(activity, .failed(.offline))
    }

    func test_loadMore_whenNextPageFails_staysLoaded() async {
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.topMoviesPage1),
            .failure(URLError(.notConnectedToInternet)),
            ])
        let viewModel = makeViewModel(movies: MovieRepository.test(client: client), shows: TVRepository.test(client: client))
        await viewModel.load()
        await viewModel.loadMore()

        guard case .loaded(let rows, let activity) = viewModel.state else {
            return XCTFail("Expected rows to remain")
        }
        XCTAssertEqual(rows.map(\.mediaID), [278, 238])
        XCTAssertEqual(activity, .failed(.offline))
    }

    func test_reloadAndRefresh_stampSavedMovieScore() async throws {
        let annotations = AnnotationsRepository.empty()
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let viewModel = makeViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            annotations: annotations
        )
        await viewModel.load()
        try await annotations.saveScore(7.5, for: .movie(278))

        await viewModel.reloadDisplayedScores()

        guard case .loaded(let rows, _) = viewModel.state else {
            return XCTFail("Expected rows after returning, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.first { $0.mediaID == 278 }?.formattedUserScore, "7.5 / 10")

        await viewModel.refresh()

        guard case .loaded(let refreshed, activity: .none) = viewModel.state else {
            return XCTFail("Expected rows after refresh, got \(viewModel.state)")
        }
        XCTAssertEqual(refreshed.first { $0.mediaID == 278 }?.formattedUserScore, "7.5 / 10")
    }

    private func makeViewModel(
        movieStub: FakeHTTPClient.Stub = .success(TMDBFixtures.topMoviesPage1)
    ) -> BrowseListViewModel {
        let client = FakeHTTPClient(stub: movieStub)
        return makeViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client)
        )
    }

    private func makeViewModel(
        movies: MovieRepository,
        shows: TVRepository,
        annotations: AnnotationsRepository = .empty()
    ) -> BrowseListViewModel {
        let day = today
        return BrowseListViewModel(
            movies: movies,
            shows: shows,
            annotations: annotations,
            locale: locale,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            today: { day }
        )
    }

    private func queryItems(_ client: RecordingHTTPClient) async -> [URLQueryItem] {
        let url = await client.lastURL
        return URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func candidate(
        _ media: BrowseCandidate.Media,
        id: Int,
        title: String,
        date: String? = nil,
        vote: Double = 1,
        popularity: Double = 0
    ) -> BrowseCandidate {
        BrowseCandidate(
            media: media,
            id: id,
            title: title,
            posterPath: nil,
            genreIDs: [],
            date: date.map(TestMovies.date),
            voteAverage: vote,
            popularity: popularity
        )
    }

    private static let emptyPage = Data(
        """
        {"page":1,"results":[],"total_pages":1,"total_results":0}
        """.utf8
    )

    private static let unknownGenrePage = Data(
        """
        {
          "page": 1,
          "results": [
            {
              "id": 1, "title": "Known", "genre_ids": [18, 424242],
              "release_date": "2024-01-12", "vote_average": 7, "vote_count": 100
            },
            {
              "id": 2, "title": "Unknown Only", "genre_ids": [424242],
              "release_date": "2024-01-12", "vote_average": 6, "vote_count": 100
            }
          ],
          "total_pages": 1,
          "total_results": 2
        }
        """.utf8
    )

    private static let tvPage = Data(
        """
        {
          "page": 1,
          "results": [
            {
              "id": 11, "name": "Middlemarch", "genre_ids": [18],
              "first_air_date": "1994-01-01", "vote_average": 9.1
            },
            {
              "id": 10, "name": "Alpha", "genre_ids": [18],
              "first_air_date": "2001-01-01", "vote_average": 8.7
            }
          ],
          "total_pages": 1,
          "total_results": 2
        }
        """.utf8
    )

    private static func moviePage(id: Int, title: String, page: Int, totalPages: Int) -> Data {
        Data(
            """
            {
              "page": \(page),
              "results": [
                {
                  "id": \(id), "title": "\(title)", "genre_ids": [18],
                  "release_date": "2020-01-01", "vote_average": 5, "vote_count": 80
                }
              ],
              "total_pages": \(totalPages),
              "total_results": 1
            }
            """.utf8
        )
    }
}

/// Holds one Discover call open so a test can start a second load while the first is in flight.
private actor PausingHTTPClient: HTTPClient {
    private let pauseOn: Int
    private let pages: [Int: Data]
    private var count = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var entered: CheckedContinuation<Void, Never>?
    private var didEnter = false
    private(set) var requestCount = 0

    init(pauseOn: Int, pages: [Int: Data]) {
        self.pauseOn = pauseOn
        self.pages = pages
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        count += 1
        let number = count
        if number == pauseOn {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (gate: CheckedContinuation<Void, Error>) in
                    continuation = gate
                    if !didEnter {
                        didEnter = true
                        entered?.resume()
                        entered = nil
                    }
                }
            } onCancel: {
                Task { await self.failGate() }
            }
        }
        let body = pages[number] ?? pages[1] ?? Data("{}".utf8)
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    func waitUntilPaused() async {
        if didEnter { return }
        await withCheckedContinuation { entered = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    private func failGate() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
