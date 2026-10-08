//
//  MovieDetailViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class MovieDetailViewModelTests: XCTestCase {

    func test_load_whenClientSucceeds_setsLoadedContent() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank))

        await viewModel.load()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.detail.id, 278)
        XCTAssertEqual(content.detail.title, "The Shawshank Redemption")
        XCTAssertEqual(content.detail.overview, "Framed in the 1940s for a double murder.")
        XCTAssertEqual(content.detail.genres.map(\.name), ["Drama", "Crime"])
        XCTAssertEqual(content.detail.runtimeMinutes, 142)
        XCTAssertEqual(content.heroMetadataLine, "1994 · 142 mins · Drama, Crime")
        XCTAssertEqual(content.heroMetadataAccessibilityLabel, "1994, 142 minutes, Drama, Crime")
        XCTAssertEqual(content.formattedRating, "8.7 / 10")
        XCTAssertEqual(content.ratingAccessibilityLabel, "Rated 8.7 out of 10")
        XCTAssertEqual(content.formattedBudget, "$25.0M")
        XCTAssertEqual(content.formattedRevenue, "$28.3M")
        XCTAssertEqual(content.formattedReleaseDate, "Sep 23, 1994")
        XCTAssertEqual(content.images?.items.map(\.filePath), ["/backdrop-a.jpg", "/backdrop-b.jpg"])
        XCTAssertEqual(content.cast?.members.map(\.name), ["Tim Robbins", "Morgan Freeman"])
        XCTAssertEqual(content.crew?.people.count, 1)
        XCTAssertEqual(content.crew?.people.first?.name, "Frank Darabont")
        XCTAssertEqual(content.crew?.people.first?.roles, ["Director", "Screenplay"])
        XCTAssertEqual(content.similar?.items.map(\.id), [311])
        XCTAssertNil(content.collection)
        XCTAssertNil(content.reviews)
    }

    func test_load_whenNoImages_hidesImagesSection() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailSparse))

        await viewModel.load()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertNil(content.images)
        XCTAssertNil(content.cast)
        XCTAssertNil(content.crew)
        XCTAssertNil(content.similar)
    }

    func test_load_whenCollectionHasOtherParts_setsCollectionSection() async {
        let client = RoutingHTTPClient(routes: [
            "/movie/238": .success(TMDBFixtures.movieDetailWithCollection),
            "/collection/230": .success(TMDBFixtures.collectionGodfather),
            "/reviews": .success(TMDBFixtures.movieReviewsEmpty),
            ])
        let viewModel = MovieDetailViewModel(
            movieID: 238,
            movies: MovieRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.collection?.title, "The Godfather Collection")
        XCTAssertEqual(content.collection?.movies.map(\.id), [240])
    }

    func test_load_whenCollectionOnlyContainsSelf_keepsCollectionEntry() async {
        let client = RoutingHTTPClient(routes: [
            "/movie/238": .success(TMDBFixtures.movieDetailWithCollection),
            "/collection/230": .success(TMDBFixtures.collectionSolo),
            "/reviews": .success(TMDBFixtures.movieReviewsEmpty),
            ])
        let viewModel = MovieDetailViewModel(
            movieID: 238,
            movies: MovieRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.collection?.id, 230)
        XCTAssertEqual(content.collection?.title, "The Godfather Collection")
        XCTAssertEqual(content.collection?.posterPath, "/collection.jpg")
        XCTAssertTrue(content.collection?.movies.isEmpty == true)
    }

    func test_load_whenReviewsExist_setsReviewsSection() async {
        let client = RoutingHTTPClient(routes: [
            "/movie/278": .success(TMDBFixtures.movieDetailShawshank),
            "/reviews": .success(TMDBFixtures.movieReviewsPage1),
            ])
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.reviews?.items.map(\.id), ["rev-1"])
        XCTAssertEqual(content.reviews?.items.first?.username, "alice_reviews")
        XCTAssertTrue(content.reviews?.hasMore == true)
    }

    func test_loadMoreReviews_appendsDedupedPage() async {
        let client = ReviewPagingHTTPClient()
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )

        await viewModel.load()
        await viewModel.loadMoreReviews()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.reviews?.items.map(\.id), ["rev-1", "rev-2"])
        XCTAssertEqual(content.reviews?.hasMore, false)
        XCTAssertFalse(
            ReviewWindow.canMoveForward(
                index: 0,
                itemCount: content.reviews?.items.count ?? 0,
                hasMore: content.reviews?.hasMore ?? true
            )
        )
    }

    func test_loadMoreReviews_cancelClearsLoadingPage() async {
        let client = GatedReviewHTTPClient()
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )
        await viewModel.load()

        let task = Task { await viewModel.loadMoreReviews() }
        await client.waitUntilSecondReview()
        task.cancel()
        await task.value

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.reviews?.isLoadingPage, false)
        XCTAssertNil(content.reviews?.pageError)
    }

    func test_load_whenReviewsFail_showsInlineError() async {
        let client = RoutingHTTPClient(routes: [
            "/movie/278": .success(TMDBFixtures.movieDetailShawshank),
            "/reviews": .failure(URLError(.notConnectedToInternet)),
            ])
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded detail, got \(viewModel.state)")
        }
        XCTAssertEqual(content.reviews?.items.count, 0)
        XCTAssertEqual(content.reviews?.pageError, .offline)
    }

    func test_reviewWindow_showsFiveAndKeepsTheRestForTheNextPage() {
        let items = (1...7).map { $0 }
        XCTAssertEqual(ReviewWindow.page(items, index: 0), [1, 2, 3, 4, 5])
        XCTAssertEqual(ReviewWindow.page(items, index: 1), [6, 7])
        XCTAssertFalse(ReviewWindow.canMoveBack(index: 0))
        XCTAssertTrue(ReviewWindow.canMoveForward(index: 0, itemCount: 7, hasMore: false))
        XCTAssertFalse(ReviewWindow.canMoveForward(index: 1, itemCount: 7, hasMore: false))
        XCTAssertTrue(ReviewWindow.canMoveForward(index: 1, itemCount: 7, hasMore: true))
        XCTAssertEqual(ReviewWindow.pageCount(totalCount: 1), 1)
        XCTAssertEqual(ReviewWindow.pageCount(totalCount: 5), 1)
        XCTAssertEqual(ReviewWindow.pageCount(totalCount: 6), 2)
        XCTAssertEqual(ReviewWindow.pageCount(totalCount: 12), 3)
    }

    func test_openImages_setsFullscreenSelection() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank))
        await viewModel.load()

        viewModel.openImages(initialID: "/backdrop-a.jpg")

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.fullscreenImages?.initialID, "/backdrop-a.jpg")
        XCTAssertEqual(content.fullscreenImages?.images.count, 2)
        XCTAssertEqual(content.fullscreenImages?.kind, .backdrop)

        viewModel.dismissImages()
        guard case .loaded(let dismissed, _) = viewModel.state else {
            return XCTFail("Expected loaded after dismiss")
        }
        XCTAssertNil(dismissed.fullscreenImages)
    }

    func test_openPoster_setsFullscreenPoster() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank))
        await viewModel.load()

        viewModel.openPoster()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.fullscreenImages?.kind, .poster)
        XCTAssertEqual(content.fullscreenImages?.images.map(\.filePath), [content.detail.posterPath].compactMap { $0 })
        XCTAssertEqual(content.fullscreenImages?.images.count, 1)
    }

    func test_load_whenSparseDetail_formatsUnavailableFields() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailSparse))

        await viewModel.load()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedBudget, "Not available")
        XCTAssertEqual(content.formattedRevenue, "Not available")
        XCTAssertEqual(content.formattedReleaseDate, "Not available")
        XCTAssertTrue(content.detail.genres.isEmpty)
        XCTAssertEqual(content.heroMetadataLine, "")
        XCTAssertNil(content.detail.runtimeMinutes)
    }

    func test_formatHeroMetadata_keepsOnlyLeadingTwoGenres() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 3, day: 1))
        let formatted = MovieDetailViewModel.formatHeroMetadata(
            releaseDate: date,
            runtimeMinutes: 98,
            genreNames: ["Drama", "Crime", "Thriller"]
        )

        XCTAssertEqual(formatted.line, "2026 · 98 mins · Drama, Crime")
        XCTAssertEqual(formatted.accessibility, "2026, 98 minutes, Drama, Crime")
    }

    func test_load_whenOffline_setsFailedOffline() async {
        let viewModel = makeViewModel(result: .failure(URLError(.notConnectedToInternet)))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_retry_afterFailure_loadsDetail() async {
        let switchable = SwitchableDetailHTTPClient(initial: .failure(URLError(.notConnectedToInternet)))
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: switchable),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed(.offline))

        await switchable.setStub(.success(TMDBFixtures.movieDetailShawshank))
        await viewModel.retry()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded after retry, got \(viewModel.state)")
        }
        XCTAssertEqual(content.detail.id, 278)
    }

    func test_load_withSavedScoreAndNote_showsThemAndDefaultsToNotes() async throws {
        let store = InMemoryAnnotationsStore()
        let annotations = AnnotationsRepository(store: store, logger: SilentLogger())
        _ = try await annotations.saveScore(7.5, for: .movie(278))
        _ = try await annotations.saveNote("A favorite", for: .movie(278))
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: DetailStubHTTPClient(detail: .success(TMDBFixtures.movieDetailShawshank))),
            annotations: annotations,
            lists: .empty()
        )

        await viewModel.load()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "7.5 / 10")
        XCTAssertEqual(content.userNote, "A favorite")
        XCTAssertTrue(PersonalDetail(
            formattedUserScore: content.formattedUserScore,
            userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
            userNote: content.userNote,
            formattedRatedOn: content.formattedRatedOn,
            formattedNotedOn: content.formattedNotedOn
        ).showsNotesFirst)
    }

    func test_load_withoutNote_staysOnDescriptionEvenWhenOverviewIsEmpty() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailSparse))

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertNil(content.userNote)
        XCTAssertNil(content.formattedUserScore)
        XCTAssertEqual(content.detail.overview, "")
        XCTAssertFalse(PersonalDetail(
            formattedUserScore: nil,
            userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
            userNote: content.userNote,
            formattedRatedOn: content.formattedRatedOn,
            formattedNotedOn: content.formattedNotedOn
        ).showsNotesFirst)
    }

    func test_saveUserScore_whenPersistenceFails_keepsPreviousScore() async throws {
        let store = InMemoryAnnotationsStore()
        let annotations = AnnotationsRepository(store: store, logger: SilentLogger())
        _ = try await annotations.saveScore(7.5, for: .movie(278))
        let viewModel = MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: DetailStubHTTPClient(detail: .success(TMDBFixtures.movieDetailShawshank))),
            annotations: annotations,
            lists: .empty()
        )
        await viewModel.load()
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        await viewModel.saveUserScore(9)

        guard case .loaded(let content, activity: .failed(let error)) = viewModel.state else {
            return XCTFail("Expected loaded with failed activity, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "7.5 / 10")
        XCTAssertEqual(error, .persistence)
    }

    func test_saveUserScore_addsTheMovieToWatched() async throws {
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank), lists: lists)
        await viewModel.load()

        let change = await viewModel.saveUserScore(8)

        XCTAssertEqual(change?.action, .added)
        XCTAssertEqual(change?.confirmation, "Added to Watched")
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let entry = try XCTUnwrap(snapshot.entries.first { $0.listID == watched.id })
        XCTAssertEqual(entry.itemID, 278)
        XCTAssertEqual(entry.title, "The Shawshank Redemption")
        XCTAssertEqual(entry.kind, .movie)
        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "8.0 / 10")
    }

    func test_saveUserScore_again_keepsTheWatchedDate() async throws {
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank), lists: lists)
        await viewModel.load()
        _ = await viewModel.saveUserScore(8)
        let first = try await lists.snapshot()
        let watched = try XCTUnwrap(first.list(.watched))
        let addedAt = try XCTUnwrap(first.entries.first { $0.listID == watched.id }?.addedAt)

        let change = await viewModel.saveUserScore(9)

        XCTAssertEqual(change?.action, .unchanged)
        let second = try await lists.snapshot()
        XCTAssertEqual(second.entries.filter { $0.listID == watched.id }.count, 1)
        XCTAssertEqual(second.entries.first { $0.listID == watched.id }?.addedAt, addedAt)
        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "9.0 / 10")
    }

    func test_saveUserScore_movesTheMovieOffWatchlist() async throws {
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank), lists: lists)
        await viewModel.load()
        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        let seeded = try await lists.snapshot()
        let watchlist = try XCTUnwrap(seeded.list(.watchlist))
        _ = try await lists.add(draft: content.detail.listItem(), listID: watchlist.id)

        let change = await viewModel.saveUserScore(8)

        XCTAssertEqual(change?.action, .added)
        XCTAssertEqual(change?.restore?.listID, watchlist.id)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 278 })
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watchlist.id && $0.itemID == 278 })
    }

    func test_saveUserScore_whenListSaveFails_keepsTheNewScore() async throws {
        let store = InMemoryListsStore()
        let lists = ListsRepository(store: store, logger: SilentLogger())
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.movieDetailShawshank), lists: lists)
        await viewModel.load()
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        let change = await viewModel.saveUserScore(8)

        XCTAssertNil(change)
        guard case .loaded(let content, activity: .failed(let error)) = viewModel.state else {
            return XCTFail("Expected loaded with failed activity, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "8.0 / 10")
        XCTAssertEqual(error, .persistence)
        await store.setSaveError(nil)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watched.id })
    }

    func test_load_withSavedScore_addsTheMovieToWatchedOnTheRatedDay() async throws {
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let rated = TestMovies.date("2020-01-15")
        _ = try await annotations.saveScore(7.5, for: .movie(278), at: rated)
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(
            stub: .success(TMDBFixtures.movieDetailShawshank),
            annotations: annotations,
            lists: lists
        )

        await viewModel.load()

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let entry = try XCTUnwrap(snapshot.entries.first { $0.listID == watched.id })
        XCTAssertEqual(entry.itemID, 278)
        XCTAssertEqual(entry.title, "The Shawshank Redemption")
        XCTAssertEqual(entry.addedAt, rated)
        guard case .loaded(_, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
    }

    func test_load_withNoteOnly_leavesWatchedEmpty() async throws {
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await annotations.saveNote("Remember this", for: .movie(278))
        let lists = ListsRepository.empty()
        let viewModel = makeViewModel(
            stub: .success(TMDBFixtures.movieDetailShawshank),
            annotations: annotations,
            lists: lists
        )

        await viewModel.load()

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watched.id })
        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertNil(content.formattedUserScore)
        XCTAssertEqual(content.userNote, "Remember this")
    }

    func test_formatCurrency_zero_isNotAvailable() {
        let formatted = MovieDetailViewModel.formatCurrency(0)
        XCTAssertEqual(formatted.display, "Not available")
    }

    // MARK: - Helpers

    private func makeViewModel(
        stub: FakeHTTPClient.Stub,
        annotations: AnnotationsRepository = .empty(),
        lists: ListsRepository = .empty()
    ) -> MovieDetailViewModel {
        MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: DetailStubHTTPClient(detail: stub)),
            annotations: annotations,
            lists: lists
        )
    }

    private func makeViewModel(result: Result<Data, Error>) -> MovieDetailViewModel {
        MovieDetailViewModel(
            movieID: 278,
            movies: MovieRepository.test(client: FakeHTTPClient(result: result)),
            annotations: AnnotationsRepository.empty(),
            lists: .empty()
        )
    }
}

/// Movie JSON for the detail request, and an empty review page so a missing list stays hidden.
private actor DetailStubHTTPClient: HTTPClient {
    private let detail: FakeHTTPClient.Stub

    init(detail: FakeHTTPClient.Stub) {
        self.detail = detail
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path.contains("/reviews") == true {
            let empty = Data(#"{"id":278,"page":1,"results":[],"total_pages":1,"total_results":0}"#.utf8)
            return try await FakeHTTPClient(stub: .success(empty)).data(for: request)
        }
        return try await FakeHTTPClient(stub: detail).data(for: request)
    }
}

private actor SwitchableDetailHTTPClient: HTTPClient {
    private var stub: FakeHTTPClient.Stub

    init(initial: FakeHTTPClient.Stub) {
        self.stub = initial
    }

    func setStub(_ stub: FakeHTTPClient.Stub) {
        self.stub = stub
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await FakeHTTPClient(stub: stub).data(for: request)
    }
}

/// Detail and the first review page succeed. The next review page waits until cancelled.
private actor GatedReviewHTTPClient: HTTPClient {
    private var reviewPage = 0
    private let gate = BlockingHTTPClient(responseData: TMDBFixtures.movieReviewsPage2)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        if path.contains("/reviews") {
            reviewPage += 1
            if reviewPage == 1 {
                return try await FakeHTTPClient(stub: .success(TMDBFixtures.movieReviewsPage1)).data(for: request)
            }
            return try await gate.data(for: request)
        }
        return try await FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank)).data(for: request)
    }

    func waitUntilSecondReview() async {
        await gate.waitUntilEntered()
    }
}

/// Detail + reviews page 1, then reviews page 2 for pagination.
private actor ReviewPagingHTTPClient: HTTPClient {
    private var reviewPage = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        if path.contains("/reviews") {
            reviewPage += 1
            let stub: FakeHTTPClient.Stub = reviewPage == 1
                ? .success(TMDBFixtures.movieReviewsPage1)
                : .success(TMDBFixtures.movieReviewsPage2)
            return try await FakeHTTPClient(stub: stub).data(for: request)
        }
        return try await FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank))
            .data(for: request)
    }
}

final class MovieHeroSelectionTests: XCTestCase {
    func test_backdropID_whenSelectionIsStillPresent_keepsIt() {
        let images = [
            MovieImage(filePath: "/a.jpg", voteAverage: 0),
            MovieImage(filePath: "/b.jpg", voteAverage: 0)
        ]
        XCTAssertEqual(MovieHeroSelection.backdropID(selected: "/b.jpg", images: images), "/b.jpg")
    }

    func test_backdropID_whenSelectionIsMissing_usesFirstImage() {
        let images = [MovieImage(filePath: "/a.jpg", voteAverage: 0)]
        XCTAssertEqual(MovieHeroSelection.backdropID(selected: "/gone.jpg", images: images), "/a.jpg")
    }

    func test_backdropID_whenThereAreNoImages_returnsNil() {
        XCTAssertNil(MovieHeroSelection.backdropID(selected: "/a.jpg", images: []))
    }
}
