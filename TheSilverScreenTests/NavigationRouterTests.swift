//
//  NavigationRouterTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class NavigationRouterTests: XCTestCase {

    func test_push_appendsRoute() {
        let router = NavigationRouter()

        router.push(.movieDetail(id: 278))

        XCTAssertEqual(router.path, [.movieDetail(id: 278)])
    }

    func test_pop_removesLastRoute() {
        let router = NavigationRouter()
        router.push(.movieDetail(id: 1))
        router.push(.movieDetail(id: 2))

        router.pop()

        XCTAssertEqual(router.path, [.movieDetail(id: 1)])
    }

    func test_popToDepth_truncatesPathForUIKitSync() {
        let router = NavigationRouter()
        router.push(.movieDetail(id: 1))
        router.push(.movieDetail(id: 2))

        router.pop(toDepth: 1)

        XCTAssertEqual(router.path, [.movieDetail(id: 1)])
    }

    func test_popToDepth_zeroClearsPath() {
        let router = NavigationRouter()
        router.push(.movieDetail(id: 1))

        router.pop(toDepth: 0)

        XCTAssertTrue(router.path.isEmpty)
    }

    func test_popToDepth_whenAlreadyAtDepth_isNoOp() {
        let router = NavigationRouter()
        router.push(.movieDetail(id: 1))

        router.pop(toDepth: 1)

        XCTAssertEqual(router.path, [.movieDetail(id: 1)])
    }

    // MARK: - Scene state restoration

    func test_routerSnapshot_codableRoundTrip() throws {
        let snapshot = RouterSnapshot(
            selectedTab: .library,
            browsePath: [.movieDetail(id: 278)],
            favoritesPath: [
                .person(id: 5),
                .personCredits(personID: 5, personName: "Tim Robbins", department: .crew),
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RouterSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func test_appRouter_snapshot_reflectsTabAndPaths() {
        let router = AppRouter()
        router.selectedTab = .library
        router.browse.push(.movieDetail(id: 1))
        router.favorites.push(.person(id: 2))

        let snapshot = router.snapshot

        XCTAssertEqual(snapshot.selectedTab, .library)
        XCTAssertEqual(snapshot.browsePath, [.movieDetail(id: 1)])
        XCTAssertEqual(snapshot.favoritesPath, [.person(id: 2)])
    }

    func test_appRouter_restore_setsTabAndPaths() {
        let router = AppRouter()

        router.restore(
            RouterSnapshot(
                selectedTab: .library,
                browsePath: [.movieDetail(id: 9)],
                favoritesPath: [.person(id: 3)]
            )
        )

        XCTAssertEqual(router.selectedTab, .library)
        XCTAssertEqual(router.browse.path, [.movieDetail(id: 9)])
        XCTAssertEqual(router.favorites.path, [.person(id: 3)])
    }

    func test_routerStateStore_saveThenLoad_returnsSnapshot() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = RouterStateStore(defaults: defaults)
        let snapshot = RouterSnapshot(
            selectedTab: .library,
            browsePath: [.movieDetail(id: 7)],
            favoritesPath: []
        )

        store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)

        store.clear()
        XCTAssertNil(store.load())
    }

    func test_routerSnapshot_legacyTopMoviesAndFavorites_decodesToBrowseRoot() throws {
        let json = """
        {
          "selectedTab": "topMovies",
          "topMoviesPath": [{ "movieDetail": { "id": 278 } }],
          "favoritesPath": [{ "person": { "id": 4 } }]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RouterSnapshot.self, from: json)

        XCTAssertEqual(decoded.selectedTab, .browse)
        XCTAssertTrue(decoded.browsePath.isEmpty)
        XCTAssertEqual(decoded.favoritesPath, [.person(id: 4)])
        XCTAssertTrue(decoded.searchPath.isEmpty)
    }

    func test_appTab_storedFavorites_decodesAsLibrary() throws {
        let json = """
        {"selectedTab":"favorites"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RouterSnapshot.self, from: json)

        XCTAssertEqual(decoded.selectedTab, .library)
    }

    func test_routerSnapshot_unknownTab_restoresBrowseRoot() throws {
        let json = """
        {"selectedTab": "notATab"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RouterSnapshot.self, from: json)

        XCTAssertEqual(decoded.selectedTab, .browse)
        XCTAssertTrue(decoded.browsePath.isEmpty)
        XCTAssertTrue(decoded.favoritesPath.isEmpty)
    }
}
