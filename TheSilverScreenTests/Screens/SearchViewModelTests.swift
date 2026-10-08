//
//  SearchViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class SearchViewModelTests: XCTestCase {

    private let emptyPage = Data("""
        {"page": 1, "total_pages": 1, "results": []}
        """.utf8)

    func test_reloadAndRefresh_stampSavedMovieScore() async throws {
        let annotations = AnnotationsRepository.empty()
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .success(emptyPage),
                "search/person": .success(emptyPage),
            ],
            annotations: annotations
        )
        viewModel.query = "shawshank"
        await viewModel.submit()
        try await annotations.saveScore(8, for: .movie(278))

        await viewModel.reloadDisplayedScores()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview after returning, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.first { $0.id == 278 }?.formattedUserScore, "8.0 / 10")

        await viewModel.refresh()

        guard case .loaded(.preview(let refreshed), activity: .none) = viewModel.state else {
            return XCTFail("Expected preview after refresh, got \(viewModel.state)")
        }
        XCTAssertEqual(refreshed.movies.first { $0.id == 278 }?.formattedUserScore, "8.0 / 10")
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
        XCTAssertFalse(viewModel.showsFilterPills)
        XCTAssertEqual(
            viewModel.shelves.map(\.title),
            ["Oscar Winners", "BAFTAs", "Emmys"]
        )
        let count = await client.requestCount
        XCTAssertEqual(count, 0)
    }

    func test_commitQueryChange_showsPreviewSectionsWithoutFilterPills() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage2),
                "search/tv": .success(TMDBFixtures.popularTVPage),
                "search/person": .success(TMDBFixtures.popularPeoplePage),
            ]
        )
        viewModel.query = "godfather"

        await viewModel.commitQueryChange()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.map(\.id), [240])
        XCTAssertEqual(sections.tv.map(\.name), ["Breaking Bad"])
        XCTAssertEqual(sections.people.map(\.name), ["Brad Pitt"])
        XCTAssertFalse(viewModel.showsFilterPills)
        XCTAssertEqual(viewModel.typeNiche, .all)
        XCTAssertNil(viewModel.genreFilter)
    }

    func test_preview_capsEachTypeAtFive() async {
        let movieRows = (1...8).map { id in
            """
            {"id": \(id), "title": "Title \(id)", "genre_ids": [18], "vote_average": 7.0, "popularity": \(Double(9 - id)), "release_date": "2020-01-01"}
            """
        }.joined(separator: ",")
        let payload = Data("""
            {"page": 1, "total_pages": 1, "results": [\(movieRows)]}
            """.utf8)
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(payload),
                "search/tv": .success(emptyPage),
                "search/person": .success(emptyPage),
            ]
        )
        viewModel.query = "Title"
        await viewModel.submit()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.count, 5)
        XCTAssertEqual(sections.movies.map(\.id), [1, 2, 3, 4, 5])
    }

    func test_openAllResults_interleavesByMatchThenPopularity() async {
        let movies = Data("""
            {
            "page": 1,
            "results": [
            {"id": 1, "title": "Other", "genre_ids": [99], "vote_average": 5.0, "popularity": 200.0, "release_date": "2020-01-01"},
            {"id": 2, "title": "Spi Movie", "genre_ids": [28], "vote_average": 8.0, "popularity": 10.0, "release_date": "2026-07-29"}
            ],
            "total_pages": 1
            }
            """.utf8)
        let people = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 9, "name": "Spi Person", "profile_path": null, "known_for_department": "Acting", "popularity": 50.0}
            ]
            }
            """.utf8)
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(movies),
                "search/tv": .success(emptyPage),
                "search/person": .success(people),
            ]
        )
        viewModel.query = "Spi"
        await viewModel.submit()
        viewModel.openAllResults()

        guard case .loaded(.allResults(let items), _) = viewModel.state else {
            return XCTFail("Expected all results, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.showsFilterPills)
        // Matches first (person 50, movie 10), then non-match Other at 200.
        XCTAssertEqual(items.map(\.displayName), ["Spi Person", "Spi Movie", "Other"])
    }

    func test_typeNiche_filtersToMoviesAndClearsOnRetap() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .success(TMDBFixtures.popularTVPage),
                "search/person": .success(TMDBFixtures.popularPeoplePage),
            ]
        )
        viewModel.query = "breaking"
        await viewModel.submit()
        viewModel.openAllResults()

        viewModel.selectTypeNiche(.movies)
        guard case .loaded(.allResults(let moviesOnly), _) = viewModel.state else {
            return XCTFail("Expected movies niche, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.typeNiche, .movies)
        XCTAssertTrue(moviesOnly.allSatisfy {
            if case .movie = $0 { return true }
            return false
        })

        viewModel.selectTypeNiche(.movies)
        XCTAssertEqual(viewModel.typeNiche, .all)
        guard case .loaded(.allResults(let all), _) = viewModel.state else {
            return XCTFail("Expected all types after clear, got \(viewModel.state)")
        }
        XCTAssertTrue(all.contains { if case .tv = $0 { return true }; return false })
        XCTAssertTrue(all.contains { if case .person = $0 { return true }; return false })
    }

    func test_genreFilter_keepsMatchingTitlesAndDropsPeople() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .success(TMDBFixtures.popularTVPage),
                "search/person": .success(TMDBFixtures.popularPeoplePage),
            ]
        )
        viewModel.query = "drama"
        await viewModel.submit()
        viewModel.openAllResults()
        viewModel.selectGenreFilter(.drama)

        guard case .loaded(.allResults(let items), _) = viewModel.state else {
            return XCTFail("Expected filtered results, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.genreFilter, .drama)
        XCTAssertFalse(items.contains { if case .person = $0 { return true }; return false })
        XCTAssertTrue(items.contains { item in
            if case .movie(let row) = item { return row.genreIDs.contains(18) }
            if case .tv(let row) = item { return !Set(row.genreIDs).isDisjoint(with: MergedGenre.drama.tvGenreIDs) }
            return false
        })
    }

    func test_queryEdit_returnsToPreviewAndClearsFilters() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .success(emptyPage),
                "search/person": .success(emptyPage),
            ]
        )
        viewModel.query = "shawshank"
        await viewModel.submit()
        viewModel.openAllResults()
        viewModel.selectTypeNiche(.movies)
        viewModel.selectGenreFilter(.drama)
        XCTAssertTrue(viewModel.showsFilterPills)

        viewModel.query = "godfather"
        await viewModel.submit()

        guard case .loaded(.preview, _) = viewModel.state else {
            return XCTFail("Expected preview after edit, got \(viewModel.state)")
        }
        XCTAssertFalse(viewModel.showsFilterPills)
        XCTAssertEqual(viewModel.typeNiche, .all)
        XCTAssertNil(viewModel.genreFilter)
    }

    func test_keyboardDismissed_keepsSearchResults() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage2),
                "search/tv": .success(emptyPage),
                "search/person": .success(emptyPage),
            ]
        )
        viewModel.query = "godfather"
        await viewModel.commitQueryChange()
        let before = viewModel.state

        viewModel.keyboardDismissed()

        XCTAssertEqual(viewModel.state, before)
        XCTAssertEqual(viewModel.query, "godfather")
    }

    func test_peopleSearch_mapsKnownForDepartment() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(emptyPage),
                "search/tv": .success(emptyPage),
                "search/person": .success(TMDBFixtures.popularPeoplePage),
            ]
        )
        viewModel.query = "pitt"
        await viewModel.commitQueryChange()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.people[0].name, "Brad Pitt")
        XCTAssertEqual(sections.people[0].knownForDepartment, "Acting")
        XCTAssertEqual(sections.people[0].profilePath, "/pitt.jpg")
    }

    func test_loadMore_appendsSecondMoviePageInAllResults() async {
        let client = SearchPagingHTTPClient(
            moviePages: [TMDBFixtures.topMoviesPage1, TMDBFixtures.topMoviesPage2],
            emptyPage: emptyPage
        )
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )

        viewModel.query = "shawshank"
        await viewModel.submit()
        viewModel.openAllResults()
        viewModel.selectTypeNiche(.movies)
        await viewModel.loadMore()

        guard case .loaded(.allResults(let items), activity: .none) = viewModel.state else {
            return XCTFail("Expected paged movies, got \(viewModel.state)")
        }
        XCTAssertEqual(items.compactMap(\.movieID), [278, 238, 240])
    }

    func test_submit_oneCharacterReplacesShelvesWithPreview() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage2),
            "search/tv": .success(emptyPage),
            "search/person": .success(emptyPage),
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

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.map(\.id), [240])
        let searchCount = await client.requests.filter { $0.url?.path.contains("search/movie") == true }.count
        XCTAssertEqual(searchCount, 1)
    }

    func test_openAllResults_reusesTypeaheadCache() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage1),
            "search/tv": .success(emptyPage),
            "search/person": .success(emptyPage),
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
        let countAfterPreview = await client.requestCount
        viewModel.openAllResults()

        let countAfterAll = await client.requestCount
        XCTAssertEqual(countAfterAll, countAfterPreview)
        guard case .loaded(.allResults(let items), _) = viewModel.state else {
            return XCTFail("Expected cached all results")
        }
        XCTAssertEqual(items.compactMap(\.movieID), [278, 238])
        XCTAssertEqual(viewModel.query, "shawshank")
    }

    func test_emptyQuery_doesNotRefetchPopular() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage2),
            "search/tv": .success(emptyPage),
            "search/person": .success(emptyPage),
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
        XCTAssertFalse(viewModel.showsFilterPills)
    }

    func test_submit_whileTheFieldIsFocusedAndEmpty_keepsThePlaceholder() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage2),
            "search/tv": .success(emptyPage),
            "search/person": .success(emptyPage),
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
        let viewModel = makeViewModel(routes: [:])
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
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(payload),
                "search/tv": .success(emptyPage),
                "search/person": .success(emptyPage),
            ]
        )
        viewModel.query = "Spi"
        await viewModel.submit()
        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.map(\.title), ["Spider-Man: Brand New Day", "SPI"])
    }

    func test_peopleSearch_misspelledName_includesTheClosePerson() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(emptyPage),
            "search/tv": .success(emptyPage),
            "query=Christopher Waltz": .success(peoplePage(id: 1, name: "Christopher Walsh", popularity: 500)),
            "query=christopher": .success(peoplePage()),
            "query=waltz": .success(peoplePage(id: 27319, name: "Christoph Waltz", popularity: 1)),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "Christopher Waltz"

        await viewModel.submit()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.people.map(\.name), ["Christoph Waltz", "Christopher Walsh"])
        let personQueries = await client.requests
            .filter { $0.url?.path.contains("search/person") == true }
            .compactMap(queryValue)
        XCTAssertEqual(personQueries.first, "Christopher Waltz")
        XCTAssertEqual(Set(personQueries.dropFirst()), ["christopher", "waltz"])
    }

    func test_peopleSearch_whenThePageAlreadyMatches_doesNotSearchTokens() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(emptyPage),
            "search/tv": .success(emptyPage),
            "search/person": .success(peoplePage(id: 27319, name: "Christoph Waltz", popularity: 10)),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "Christopher Waltz"

        await viewModel.submit()

        let personCount = await client.requests.filter { $0.url?.path.contains("search/person") == true }.count
        XCTAssertEqual(personCount, 1)
        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.people.map(\.name), ["Christoph Waltz"])
    }

    func test_typingGenreName_searchesTitlesNotDiscover() async {
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage1),
            "search/tv": .success(emptyPage),
            "search/person": .success(emptyPage),
            "discover/movie": .success(TMDBFixtures.topMoviesPage2),
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

        let paths = await client.requests.compactMap { $0.url?.path }
        XCTAssertTrue(paths.contains { $0.contains("search/movie") })
        XCTAssertFalse(paths.contains { $0.contains("discover/movie") })
    }

    func test_focusedPlaceholder_asksForAName() {
        let viewModel = makeViewModel(routes: [:])
        viewModel.setFieldFocused(true)
        XCTAssertEqual(viewModel.emptyMessage, "Type a name")
    }

    func test_emphasis_whenPersonOutranksTitle_isPeopleFirst() async {
        let movies = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 2, "title": "Brad Documentary", "genre_ids": [99], "vote_average": 5.0, "popularity": 10.0, "release_date": "2020-01-01"}
            ]
            }
            """.utf8)
        let people = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 287, "name": "Brad Pitt", "profile_path": "/pitt.jpg", "known_for_department": "Acting", "popularity": 80.0}
            ]
            }
            """.utf8)
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(movies),
                "search/tv": .success(emptyPage),
                "search/person": .success(people),
            ]
        )
        viewModel.query = "Brad"
        await viewModel.submit()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.emphasis, .peopleFirst)
        XCTAssertEqual(sections.people.map(\.name), ["Brad Pitt"])

        viewModel.openAllResults()
        guard case .loaded(.allResults(let items), _) = viewModel.state else {
            return XCTFail("Expected all results, got \(viewModel.state)")
        }
        XCTAssertEqual(items.first?.displayName, "Brad Pitt")
        XCTAssertTrue(items.contains { $0.displayName == "Brad Documentary" })
    }

    func test_emphasis_whenTitleOutranksPerson_isTitlesFirst() async {
        let people = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 9, "name": "Godfrey", "profile_path": null, "known_for_department": "Acting", "popularity": 1.0}
            ]
            }
            """.utf8)
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage2),
                "search/tv": .success(emptyPage),
                "search/person": .success(people),
            ]
        )
        viewModel.query = "godfather"
        await viewModel.submit()

        guard case .loaded(.preview(let sections), _) = viewModel.state else {
            return XCTFail("Expected preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.emphasis, .titlesFirst)
        XCTAssertEqual(sections.movies.map(\.id), [240])
    }

    func test_emphasis_frozenAcrossRefreshThatWouldFlip() async {
        let personStrong = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 9, "name": "Spi Person", "profile_path": null, "known_for_department": "Acting", "popularity": 100.0}
            ]
            }
            """.utf8)
        let personWeak = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 9, "name": "Spi Person", "profile_path": null, "known_for_department": "Acting", "popularity": 1.0}
            ]
            }
            """.utf8)
        let movieWeak = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 2, "title": "Spi Movie", "genre_ids": [28], "vote_average": 8.0, "popularity": 10.0, "release_date": "2026-07-29"}
            ]
            }
            """.utf8)
        let movieStrong = Data("""
            {
            "page": 1,
            "total_pages": 1,
            "results": [
            {"id": 2, "title": "Spi Movie", "genre_ids": [28], "vote_average": 8.0, "popularity": 200.0, "release_date": "2026-07-29"}
            ]
            }
            """.utf8)
        let client = SearchEmphasisFlipHTTPClient(
            firstMovie: movieWeak,
            firstPerson: personStrong,
            secondMovie: movieStrong,
            secondPerson: personWeak,
            emptyPage: emptyPage
        )
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "Spi"
        await viewModel.submit()
        guard case .loaded(.preview(let first), _) = viewModel.state else {
            return XCTFail("Expected people-first preview, got \(viewModel.state)")
        }
        XCTAssertEqual(first.emphasis, .peopleFirst)

        await viewModel.refresh()
        guard case .loaded(.preview(let refreshed), _) = viewModel.state else {
            return XCTFail("Expected frozen preview after refresh, got \(viewModel.state)")
        }
        XCTAssertEqual(refreshed.emphasis, .peopleFirst)
        // Fresh scores would prefer the title (200 > 1); freeze must win.
        let recomputed = SearchResultEmphasisResolver.emphasis(
            movies: [.movie(CatalogMovieRow(movie: Movie(
                id: 2,
                title: "Spi Movie",
                posterPath: nil,
                releaseDate: nil,
                voteAverage: 8,
                genreIDs: [28],
                popularity: 200
            )))],
            tv: [],
            people: [.person(CatalogPersonRow(person: PersonSummary(
                id: 9,
                name: "Spi Person",
                profilePath: nil,
                knownForDepartment: "Acting",
                popularity: 1
            )))],
            query: "Spi"
        )
        XCTAssertEqual(recomputed, .titlesFirst)
    }

    func test_submit_whenOffline_setsFailedState() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .failure(URLError(.notConnectedToInternet)),
                "search/tv": .failure(URLError(.notConnectedToInternet)),
                "search/person": .failure(URLError(.notConnectedToInternet)),
            ]
        )
        viewModel.query = "dune"
        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_refresh_whenOffline_keepsLoadedPreview() async {
        let client = SearchOfflineToggleHTTPClient(
            movie: TMDBFixtures.topMoviesPage1,
            tv: emptyPage,
            person: emptyPage
        )
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "shawshank"
        await viewModel.submit()
        await client.setOffline(true)
        await viewModel.refresh()

        guard case .loaded(.preview(let sections), let activity) = viewModel.state else {
            return XCTFail("Expected preview to stay up, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.map(\.id), [278, 238])
        XCTAssertEqual(activity, .failed(.offline))
    }

    func test_partialTypeFailure_stillPublishesSuccessfulTypes() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .failure(URLError(.notConnectedToInternet)),
                "search/person": .success(TMDBFixtures.popularPeoplePage),
            ]
        )
        viewModel.query = "drama"
        await viewModel.submit()

        guard case .loaded(.preview(let sections), let activity) = viewModel.state else {
            return XCTFail("Expected partial preview, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.map(\.id), [278, 238])
        XCTAssertTrue(sections.tv.isEmpty)
        XCTAssertEqual(sections.people.map(\.name), ["Brad Pitt"])
        XCTAssertEqual(activity, .failed(.offline))
    }

    func test_typeNiche_filtersToTVAndPeople() async {
        let viewModel = makeViewModel(
            routes: [
                "search/movie": .success(TMDBFixtures.topMoviesPage1),
                "search/tv": .success(TMDBFixtures.popularTVPage),
                "search/person": .success(TMDBFixtures.popularPeoplePage),
            ]
        )
        viewModel.query = "breaking"
        await viewModel.submit()
        viewModel.openAllResults()

        viewModel.selectTypeNiche(.tv)
        guard case .loaded(.allResults(let tvOnly), _) = viewModel.state else {
            return XCTFail("Expected TV niche, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.typeNiche, .tv)
        XCTAssertTrue(tvOnly.allSatisfy {
            if case .tv = $0 { return true }
            return false
        })
        XCTAssertFalse(tvOnly.isEmpty)

        viewModel.selectTypeNiche(.people)
        guard case .loaded(.allResults(let peopleOnly), _) = viewModel.state else {
            return XCTFail("Expected people niche, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.typeNiche, .people)
        XCTAssertTrue(peopleOnly.allSatisfy {
            if case .person = $0 { return true }
            return false
        })
        XCTAssertFalse(peopleOnly.isEmpty)
    }

    func test_newerQuery_cancelsInFlightFetch() async {
        let client = SearchQueryGateHTTPClient(
            blockedQuery: "slow",
            payloads: [
                "search/movie": TMDBFixtures.topMoviesPage2,
                "search/tv": emptyPage,
                "search/person": emptyPage,
            ]
        )
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )

        let slow = Task {
            viewModel.query = "slow"
            await viewModel.submit()
        }
        await client.waitUntilBlocked()
        viewModel.query = "godfather"
        await viewModel.submit()
        await client.releaseBlocked()
        await slow.value

        guard case .loaded(.preview(let sections), activity: .none) = viewModel.state else {
            return XCTFail("Expected newer query to win, got \(viewModel.state)")
        }
        XCTAssertEqual(sections.movies.map(\.id), [240])
        XCTAssertEqual(viewModel.committedQuery, "godfather")
    }

    func test_loadMore_staleToken_doesNotStickOnLoadingMore() async {
        let client = SearchLoadMoreGateHTTPClient(
            moviePages: [TMDBFixtures.topMoviesPage1, TMDBFixtures.topMoviesPage2],
            emptyPage: emptyPage
        )
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: NoopSleeper()
        )
        viewModel.query = "shawshank"
        await viewModel.submit()
        viewModel.openAllResults()
        viewModel.selectTypeNiche(.movies)

        let paging = Task { await viewModel.loadMore() }
        await client.waitUntilSecondMoviePage()
        viewModel.query = "godfather"
        await viewModel.submit(query: "godfather")
        await client.releaseSecondMoviePage()
        await paging.value

        guard case .loaded(_, let activity) = viewModel.state else {
            return XCTFail("Expected loaded after stale page, got \(viewModel.state)")
        }
        XCTAssertNotEqual(activity, .loadingMore)
        XCTAssertEqual(activity, .none)
    }

    func test_scheduleQueryChange_cancelDebounce_skipsSubmit() async {
        let sleeper = HoldSleeper()
        let client = RoutingHTTPClient(routes: [
            "search/movie": .success(TMDBFixtures.topMoviesPage1),
            "search/tv": .success(emptyPage),
            "search/person": .success(emptyPage),
        ])
        let viewModel = SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            sleeper: sleeper
        )
        viewModel.query = "shawshank"
        viewModel.scheduleQueryChange()
        await sleeper.waitUntilSleeping()
        viewModel.cancelDebounce()
        await sleeper.release()

        let count = await client.requestCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(viewModel.state, .idle)
    }

    private func peoplePage(id: Int = 0, name: String? = nil, popularity: Double = 0) -> Data {
        let results: String
        if let name {
            results = """
            {"id": \(id), "name": "\(name)", "profile_path": null, "known_for_department": "Acting", "popularity": \(popularity)}
            """
        } else {
            results = ""
        }
        return Data(
            """
            {"page": 1, "total_pages": 1, "results": [\(results)]}
            """.utf8
        )
    }

    private func queryValue(_ request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "query" }?
            .value
    }

    private func queryItems(_ client: RecordingHTTPClient) async -> [URLQueryItem] {
        let url = await client.lastURL
        return URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func makeViewModel(
        routes: [String: FakeHTTPClient.Stub],
        annotations: AnnotationsRepository = .empty()
    ) -> SearchViewModel {
        var merged = [
            "search/movie": FakeHTTPClient.Stub.success(emptyPage),
            "search/tv": FakeHTTPClient.Stub.success(emptyPage),
            "search/person": FakeHTTPClient.Stub.success(emptyPage),
        ]
        for (key, stub) in routes {
            merged[key] = stub
        }
        let client = RoutingHTTPClient(routes: merged)
        return SearchViewModel(
            movies: MovieRepository.test(client: client),
            shows: TVRepository.test(client: client),
            people: PersonRepository.test(client: client),
            annotations: annotations,
            sleeper: NoopSleeper()
        )
    }
}

private extension SearchResultItem {
    var movieID: Int? {
        if case .movie(let row) = self { return row.id }
        return nil
    }
}

/// Returns successive movie search pages; TV and people always get an empty page.
private actor SearchPagingHTTPClient: HTTPClient {
    private var moviePages: [Data]
    private var movieIndex = 0
    private let emptyPage: Data

    init(moviePages: [Data], emptyPage: Data) {
        self.moviePages = moviePages
        self.emptyPage = emptyPage
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let payload: Data
        if path.contains("search/movie") {
            let index = min(movieIndex, moviePages.count - 1)
            payload = moviePages[index]
            movieIndex += 1
        } else {
            payload = emptyPage
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (payload, response)
    }
}

/// Serves success payloads until `setOffline(true)`, then fails with offline.
private actor SearchOfflineToggleHTTPClient: HTTPClient {
    private let movie: Data
    private let tv: Data
    private let person: Data
    private var offline = false

    init(movie: Data, tv: Data, person: Data) {
        self.movie = movie
        self.tv = tv
        self.person = person
    }

    func setOffline(_ value: Bool) {
        offline = value
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if offline {
            throw URLError(.notConnectedToInternet)
        }
        let path = request.url?.path ?? ""
        let payload: Data
        if path.contains("search/movie") {
            payload = movie
        } else if path.contains("search/tv") {
            payload = tv
        } else if path.contains("search/person") {
            payload = person
        } else {
            throw URLError(.badURL)
        }
        return (
            payload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

/// Blocks the first wave of requests for `blockedQuery`, then lets later queries through.
private actor SearchQueryGateHTTPClient: HTTPClient {
    private let blockedQuery: String
    private let payloads: [String: Data]
    private var isReleased = false
    private var didEnter = false
    private var releaseContinuation: CheckedContinuation<Void, Error>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    init(blockedQuery: String, payloads: [String: Data]) {
        self.blockedQuery = blockedQuery
        self.payloads = payloads
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "query" }?
            .value
        // Gate only the movie request so parallel TV/people for the same query do not hang.
        if query == blockedQuery, path.contains("search/movie") {
            try await withTaskCancellationHandler {
                if !isReleased {
                    try await withCheckedThrowingContinuation { (gate: CheckedContinuation<Void, Error>) in
                        if isReleased {
                            gate.resume()
                            markEntered()
                            return
                        }
                        releaseContinuation = gate
                        markEntered()
                    }
                }
            } onCancel: {
                Task { await self.failGate() }
            }
        }

        guard let key = payloads.keys.first(where: { path.contains($0) }),
              let payload = payloads[key] else {
            throw URLError(.badURL)
        }
        return (
            payload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    func waitUntilBlocked() async {
        if didEnter { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func releaseBlocked() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func failGate() {
        releaseContinuation?.resume(throwing: CancellationError())
        releaseContinuation = nil
    }

    private func markEntered() {
        guard !didEnter else { return }
        didEnter = true
        enteredContinuation?.resume()
        enteredContinuation = nil
    }
}

/// Pauses on the second movie search page so a newer submit can cancel paging.
private actor SearchLoadMoreGateHTTPClient: HTTPClient {
    private var moviePages: [Data]
    private var movieIndex = 0
    private let emptyPage: Data
    private var isReleased = false
    private var didEnter = false
    private var releaseContinuation: CheckedContinuation<Void, Error>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    init(moviePages: [Data], emptyPage: Data) {
        self.moviePages = moviePages
        self.emptyPage = emptyPage
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let payload: Data
        if path.contains("search/movie") {
            let index = movieIndex
            movieIndex += 1
            payload = moviePages[min(index, moviePages.count - 1)]
            // Only the true second page waits; later movie requests must not re-enter the gate.
            if index == 1 {
                try await withTaskCancellationHandler {
                    if !isReleased {
                        try await withCheckedThrowingContinuation { (gate: CheckedContinuation<Void, Error>) in
                            if isReleased {
                                gate.resume()
                                markEntered()
                                return
                            }
                            releaseContinuation = gate
                            markEntered()
                        }
                    }
                } onCancel: {
                    Task { await self.failGate() }
                }
            }
        } else {
            payload = emptyPage
        }
        return (
            payload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    func waitUntilSecondMoviePage() async {
        if didEnter { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func releaseSecondMoviePage() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func failGate() {
        releaseContinuation?.resume(throwing: CancellationError())
        releaseContinuation = nil
    }

    private func markEntered() {
        guard !didEnter else { return }
        didEnter = true
        enteredContinuation?.resume()
        enteredContinuation = nil
    }
}

/// First wave prefers people; second wave would prefer titles — used to prove freeze.
private actor SearchEmphasisFlipHTTPClient: HTTPClient {
    private let firstMovie: Data
    private let firstPerson: Data
    private let secondMovie: Data
    private let secondPerson: Data
    private let emptyPage: Data
    private var movieRequests = 0
    private var personRequests = 0

    init(
        firstMovie: Data,
        firstPerson: Data,
        secondMovie: Data,
        secondPerson: Data,
        emptyPage: Data
    ) {
        self.firstMovie = firstMovie
        self.firstPerson = firstPerson
        self.secondMovie = secondMovie
        self.secondPerson = secondPerson
        self.emptyPage = emptyPage
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let payload: Data
        if path.contains("search/movie") {
            movieRequests += 1
            payload = movieRequests == 1 ? firstMovie : secondMovie
        } else if path.contains("search/person") {
            personRequests += 1
            payload = personRequests == 1 ? firstPerson : secondPerson
        } else {
            payload = emptyPage
        }
        return (
            payload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

/// Suspends inside `sleep` until `release()` or task cancellation — for debounce cancel tests.
private actor HoldSleeper: Sleeper {
    private var gate: CheckedContinuation<Void, Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var didEnter = false

    func sleep(seconds: TimeInterval) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                gate = continuation
                if !didEnter {
                    didEnter = true
                    waiting?.resume()
                    waiting = nil
                }
            }
        } onCancel: {
            Task { await self.cancelGate() }
        }
    }

    func waitUntilSleeping() async {
        if didEnter { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    private func cancelGate() {
        gate?.resume(throwing: CancellationError())
        gate = nil
    }
}
