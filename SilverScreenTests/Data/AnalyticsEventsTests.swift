//
//  AnalyticsEventsTests.swift
//  SilverScreenTests
//
//  Which saves report which product event. Events are sent by the repositories,
//  after the write is persisted, so every screen that saves reports the same way.
//  Real repositories over in-memory stores, with a spy at the analytics boundary.
//

import XCTest
@testable import SilverScreen

@MainActor
final class AnalyticsEventsTests: XCTestCase {
    private let movie = ListItemDraft(
        id: 278,
        kind: .movie,
        title: "The Shawshank Redemption",
        imagePath: nil,
        releaseDate: nil,
        genreNames: ["Drama"],
        voteAverage: 8.7,
        popularity: 90
    )

    // MARK: - List created

    func test_libraryViewModelCreateList_sendsListCreated() async {
        let spy = SpyAnalyticsClient()
        let viewModel = LibraryHomeViewModel(lists: makeLists(spy: spy))
        await viewModel.load()

        let saved = await viewModel.createList(named: "Noir")

        XCTAssertTrue(saved)
        XCTAssertEqual(spy.events, [.listCreated])
    }

    func test_createListWithTitle_sendsOnlyListCreated() async throws {
        let spy = SpyAnalyticsClient()
        let lists = makeLists(spy: spy)

        _ = try await lists.createList(name: "Noir", segment: .moviesAndTV, adding: movie)

        XCTAssertEqual(spy.events, [.listCreated])
    }

    func test_libraryViewModelCreateList_whenNameRejected_sendsNothing() async {
        let spy = SpyAnalyticsClient()
        let viewModel = LibraryHomeViewModel(lists: makeLists(spy: spy))
        await viewModel.load()

        let saved = await viewModel.createList(named: "Watchlist")

        XCTAssertFalse(saved)
        XCTAssertEqual(spy.events, [])
    }

    func test_createList_whenSaveFails_sendsNothing() async throws {
        let spy = SpyAnalyticsClient()
        let store = InMemoryListsStore()
        let lists = ListsRepository(store: store, logger: SilentLogger(), analytics: spy)
        _ = try await lists.snapshot()
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        _ = try? await lists.createList(name: "Noir", segment: .moviesAndTV)

        XCTAssertEqual(spy.events, [])
    }

    // MARK: - Watchlist

    func test_toggleOntoWatchlist_sendsTitleAddedToWatchlist() async throws {
        let spy = SpyAnalyticsClient()
        let lists = makeLists(spy: spy)
        let watchlist = try await systemListID(.watchlist, in: lists)

        _ = try await lists.toggle(draft: movie, listID: watchlist)

        XCTAssertEqual(spy.events, [.titleAddedToWatchlist])
    }

    func test_toggleOffWatchlist_sendsNothingMore() async throws {
        let spy = SpyAnalyticsClient()
        let lists = makeLists(spy: spy)
        let watchlist = try await systemListID(.watchlist, in: lists)
        _ = try await lists.toggle(draft: movie, listID: watchlist)

        _ = try await lists.toggle(draft: movie, listID: watchlist)

        XCTAssertEqual(spy.events, [.titleAddedToWatchlist])
    }

    func test_addAlreadyOnWatchlist_sendsNothingMore() async throws {
        let spy = SpyAnalyticsClient()
        let lists = makeLists(spy: spy)
        let watchlist = try await systemListID(.watchlist, in: lists)
        _ = try await lists.add(draft: movie, listID: watchlist)

        _ = try await lists.add(draft: movie, listID: watchlist)

        XCTAssertEqual(spy.events, [.titleAddedToWatchlist])
    }

    func test_addToWatchedOrCustomList_sendsNoWatchlistEvent() async throws {
        let spy = SpyAnalyticsClient()
        let lists = makeLists(spy: spy)
        let custom = try await lists.createList(name: "Noir", segment: .moviesAndTV).list

        _ = try await lists.addToWatched(movie)
        _ = try await lists.add(draft: movie, listID: custom.id)

        XCTAssertEqual(spy.events, [.listCreated])
    }

    // MARK: - First rating

    func test_firstScore_sendsFirstRating() async throws {
        let spy = SpyAnalyticsClient()
        let annotations = makeAnnotations(spy: spy)

        _ = try await annotations.save(score: 8, note: "", for: .movie(278))

        XCTAssertEqual(spy.events, [.firstRating])
    }

    func test_laterScores_doNotSendFirstRatingAgain() async throws {
        let spy = SpyAnalyticsClient()
        let annotations = makeAnnotations(spy: spy)
        _ = try await annotations.saveScore(8, for: .movie(278))

        _ = try await annotations.saveScore(9, for: .movie(278))
        _ = try await annotations.save(score: 6, note: "Fine", for: .movie(680))

        XCTAssertEqual(spy.events, [.firstRating])
    }

    func test_firstScore_whenSaveFails_sendsNothing() async {
        let spy = SpyAnalyticsClient()
        let store = InMemoryAnnotationsStore()
        let annotations = AnnotationsRepository(store: store, logger: SilentLogger(), analytics: spy)
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        _ = try? await annotations.saveScore(8, for: .movie(278))

        XCTAssertEqual(spy.events, [])
    }

    func test_invalidScore_sendsNothing() async {
        let spy = SpyAnalyticsClient()
        let annotations = makeAnnotations(spy: spy)

        _ = try? await annotations.saveScore(11, for: .movie(278))

        XCTAssertEqual(spy.events, [])
    }

    // MARK: - Helpers

    private func makeLists(spy: SpyAnalyticsClient) -> ListsRepository {
        ListsRepository(store: InMemoryListsStore(), logger: SilentLogger(), analytics: spy)
    }

    private func makeAnnotations(spy: SpyAnalyticsClient) -> AnnotationsRepository {
        AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger(), analytics: spy)
    }

    private func systemListID(_ system: SystemListKind, in lists: ListsRepository) async throws -> UUID {
        let snapshot = try await lists.snapshot()
        return try XCTUnwrap(snapshot.list(system)?.id)
    }
}
