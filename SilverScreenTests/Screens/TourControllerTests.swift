//
//  TourControllerTests.swift
//  SilverScreenTests
//
//  The feature tour: which stops it plans, where each stop takes the app, and
//  how reported frames become the highlight.
//

import XCTest
@testable import SilverScreen

@MainActor
final class TourControllerTests: XCTestCase {
    // MARK: - Plan

    func test_plan_withoutWatchedTitles_hasTheFourAppStops() async throws {
        let snapshot = try await ListsRepository.empty().snapshot()

        XCTAssertEqual(TourStop.plan(for: snapshot), [.libraryLists, .newList, .eyeButton, .awards])
    }

    func test_plan_withWatchedMovieAndSeries_addsDetailStops() async throws {
        let lists = ListsRepository.empty()
        _ = try await lists.addToWatched(OnboardingFixtures.movieDraft(id: 278, title: "Shawshank"))
        _ = try await lists.addToWatched(OnboardingFixtures.seriesDraft(id: 1396, title: "Breaking Bad"))

        let stops = TourStop.plan(for: try await lists.snapshot())

        XCTAssertEqual(stops.suffix(2), [
            .rateMovie(id: 278, title: "Shawshank"),
            .trackSeries(id: 1396, title: "Breaking Bad"),
        ])
    }

    // MARK: - Navigation

    func test_start_opensLibraryRootOnFirstStop() async {
        let router = AppRouter()
        router.favorites.push(.movieDetail(id: 1))
        let tour = TourController(router: router, lists: .empty())

        await tour.start()

        XCTAssertEqual(tour.current, .libraryLists)
        XCTAssertEqual(tour.progressText, "1 of 4")
        XCTAssertEqual(router.selectedTab, .library)
        XCTAssertTrue(router.favorites.path.isEmpty)
    }

    func test_next_movesAcrossTabs() async {
        let router = AppRouter()
        let tour = TourController(router: router, lists: .empty())
        await tour.start()

        tour.next()
        tour.next()
        XCTAssertEqual(router.selectedTab, .browse)

        tour.next()
        XCTAssertEqual(tour.current, .awards)
        XCTAssertEqual(router.selectedTab, .search)
    }

    func test_detailStops_pushOntoTheLibraryStack() async throws {
        let lists = ListsRepository.empty()
        _ = try await lists.addToWatched(OnboardingFixtures.movieDraft(id: 278))
        _ = try await lists.addToWatched(OnboardingFixtures.seriesDraft(id: 1396))
        let router = AppRouter()
        let tour = TourController(router: router, lists: lists)
        await tour.start()

        for _ in 0..<4 { tour.next() }
        XCTAssertEqual(router.selectedTab, .library)
        XCTAssertEqual(router.favorites.path, [.movieDetail(id: 278)])

        tour.next()
        XCTAssertEqual(router.favorites.path, [.tvSeries(id: 1396)])
        XCTAssertTrue(tour.isLastStop)
    }

    func test_nextOnLastStop_endsOnLibraryRoot() async {
        let router = AppRouter()
        let tour = TourController(router: router, lists: .empty())
        await tour.start()

        for _ in 0..<4 { tour.next() }

        XCTAssertFalse(tour.isActive)
        XCTAssertEqual(router.selectedTab, .library)
        XCTAssertTrue(router.favorites.path.isEmpty)
    }

    func test_skip_endsOnLibraryRoot() async {
        let router = AppRouter()
        let tour = TourController(router: router, lists: .empty())
        await tour.start()
        tour.next()
        tour.next()

        tour.skip()

        XCTAssertFalse(tour.isActive)
        XCTAssertNil(tour.highlight)
        XCTAssertEqual(router.selectedTab, .library)
    }

    // MARK: - Highlight

    func test_highlight_isUnionOfVisibleAnchors() async {
        let tour = TourController(router: AppRouter(), lists: .empty())
        await tour.start()

        tour.report(.libraryWatched, frame: CGRect(x: 0, y: 100, width: 300, height: 60), isVisible: true)
        tour.report(.libraryWatchlist, frame: CGRect(x: 0, y: 220, width: 300, height: 60), isVisible: true)

        XCTAssertEqual(tour.highlight, CGRect(x: 0, y: 100, width: 300, height: 180))
    }

    func test_highlight_ignoresHiddenAnchors() async {
        let tour = TourController(router: AppRouter(), lists: .empty())
        await tour.start()
        tour.report(.libraryWatched, frame: CGRect(x: 0, y: 100, width: 300, height: 60), isVisible: true)

        tour.report(.libraryWatched, frame: nil, isVisible: false)

        XCTAssertNil(tour.highlight)
    }

    func test_frameReportedBeforeItsStop_isUsedWhenTheStopOpens() async {
        let tour = TourController(router: AppRouter(), lists: .empty())
        tour.report(.newList, frame: CGRect(x: 320, y: 50, width: 44, height: 44), isVisible: true)
        await tour.start()

        tour.next()

        XCTAssertEqual(tour.highlight, CGRect(x: 320, y: 50, width: 44, height: 44))
    }

    // MARK: - Onboarding hand-off

    func test_onboardingFinish_startsTheTour() async {
        let suiteName = "test.tour.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let router = AppRouter()
        let lists = ListsRepository.empty()
        let tour = TourController(router: router, lists: lists)
        let gate = OnboardingGate(
            marker: OnboardingMarkerStore(defaults: defaults),
            lists: lists,
            annotations: .empty(),
            isDemo: false,
            router: router,
            analytics: DisabledAnalytics(),
            tour: tour
        )

        await gate.finish()

        XCTAssertEqual(tour.current, .libraryLists)
    }

    func test_onboardingSkip_doesNotStartTheTour() {
        let suiteName = "test.tour.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let router = AppRouter()
        let lists = ListsRepository.empty()
        let tour = TourController(router: router, lists: lists)
        let gate = OnboardingGate(
            marker: OnboardingMarkerStore(defaults: defaults),
            lists: lists,
            annotations: .empty(),
            isDemo: false,
            router: router,
            analytics: DisabledAnalytics(),
            tour: tour
        )

        gate.skip()

        XCTAssertFalse(tour.isActive)
    }
}
