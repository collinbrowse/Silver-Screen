//
//  CollectionViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

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
        XCTAssertEqual(content.parts[0].formattedReleaseDate, "1972")
    }

    func test_reloadDisplayedScores_keepsAListSaveFailureRaisedDuringTheAwait() async {
        let store = GatedAnnotationsStore(records: [
            MediaAnnotation(key: .movie(238), score: 8, note: nil, watchedAt: nil),
        ])
        let viewModel = CollectionViewModel(
            collectionID: 230,
            movies: MovieRepository.test(
                client: FakeHTTPClient(stub: .success(TMDBFixtures.collectionGodfather))
            ),
            annotations: AnnotationsRepository(store: store, logger: SilentLogger())
        )

        let loading = Task { await viewModel.load() }
        await store.waitUntilGated()
        viewModel.noteListSaveFailed()
        await store.release()
        await loading.value

        guard case .loaded(let content, let activity) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertNotNil(content.parts.first { $0.id == 238 }?.formattedUserScore)
        XCTAssertEqual(activity, .failed(.persistence))
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

    func test_load_whenCancelled_returnsToIdleSoTheNextAppearanceLoadsAgain() async {
        let viewModel = CollectionViewModel(
            collectionID: 230,
            movies: MovieRepository.test(client: FakeHTTPClient(stub: .failure(CancellationError()))),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .idle = viewModel.state else {
            return XCTFail("Expected idle, got \(viewModel.state)")
        }
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

/// Holds the first `load()` open until `release()`, so a test can change the screen while a
/// score stamp is waiting on the store.
private actor GatedAnnotationsStore: AnnotationsStore {
    private let records: [MediaAnnotation]
    private var isReleased = false
    private var gate: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var didEnter = false

    init(records: [MediaAnnotation]) {
        self.records = records
    }

    func load() async throws -> [MediaAnnotation] {
        if !isReleased {
            await withCheckedContinuation { continuation in
                gate = continuation
                didEnter = true
                entered?.resume()
                entered = nil
            }
        }
        return records
    }

    func save(_ records: [MediaAnnotation]) async throws {}

    func waitUntilGated() async {
        if didEnter { return }
        await withCheckedContinuation { entered = $0 }
    }

    func release() {
        isReleased = true
        gate?.resume()
        gate = nil
    }
}
