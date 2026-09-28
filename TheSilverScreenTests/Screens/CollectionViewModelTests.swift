//
//  CollectionViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class CollectionViewModelTests: XCTestCase {

    func test_load_mapsHeaderAndParts() async {
        let viewModel = CollectionViewModel(
            collectionID: 230,
            movies: MovieRepository.test(
                client: FakeHTTPClient(stub: .success(TMDBFixtures.collectionGodfather))
            ),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.name, "The Godfather Collection")
        XCTAssertEqual(content.overview, "The Corleone family saga.")
        XCTAssertEqual(content.posterPath, "/collection.jpg")
        XCTAssertEqual(content.parts.map(\.title), ["The Godfather", "The Godfather Part II"])
        XCTAssertEqual(content.parts[0].genreNames, ["Drama"])
        XCTAssertEqual(content.parts[0].formattedReleaseDate, "Mar 14, 1972")
    }

    func test_load_sortsUndatedPartsBeforeOldestRelease() async {
        let viewModel = CollectionViewModel(
            collectionID: 1,
            movies: MovieRepository.test(client: FakeHTTPClient(stub: .success(Self.unsortedParts))),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.parts.map(\.title), ["Undated", "Older", "Newer"])
    }

    func test_load_whenPosterOverviewAndPartsAreEmpty_setsEmpty() async {
        let viewModel = CollectionViewModel(
            collectionID: 1,
            movies: MovieRepository.test(client: FakeHTTPClient(stub: .success(Self.emptyCollection))),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
    }

    func test_load_whenOffline_setsFailed() async {
        let viewModel = CollectionViewModel(
            collectionID: 230,
            movies: MovieRepository.test(
                client: FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
            ),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    private static let unsortedParts = Data(
        """
        {
          "id": 1,
          "name": "Years",
          "overview": "Dates.",
          "poster_path": "/p.jpg",
          "parts": [
            {"id": 3, "title": "Newer", "release_date": "2020-01-01", "vote_average": 1, "genre_ids": []},
            {"id": 1, "title": "Undated", "release_date": "", "vote_average": 1, "genre_ids": []},
            {"id": 2, "title": "Older", "release_date": "1990-05-01", "vote_average": 1, "genre_ids": []}
          ]
        }
        """.utf8
    )

    private static let emptyCollection = Data(
        """
        {"id": 1, "name": "Empty", "overview": "  ", "poster_path": "", "parts": []}
        """.utf8
    )
}
