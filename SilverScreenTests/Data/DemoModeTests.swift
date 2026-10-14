//
//  DemoModeTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class DemoModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_from_withoutFlag_returnsNil() {
        let environment = [DemoMode.seedKey: "/tmp/titles.json"]

        XCTAssertNil(DemoMode.from(environment: environment))
    }

    func test_from_withFlag_readsSeedPathAndRoute() {
        let environment = [
            DemoMode.enabledKey: "1",
            DemoMode.seedKey: "/tmp/titles.json",
            DemoMode.routeKey: #"{"selectedTab":"search","searchPath":[{"movieDetail":{"id":550}}]}"#,
        ]

        let demo = DemoMode.from(environment: environment)

        XCTAssertEqual(demo?.seedURL, URL(fileURLWithPath: "/tmp/titles.json"))
        XCTAssertEqual(
            demo?.routerSnapshot,
            RouterSnapshot(selectedTab: .search, searchPath: [.movieDetail(id: 550)])
        )
    }

    func test_from_withUnreadableRoute_keepsDemoModeWithoutRoute() {
        let environment = [DemoMode.enabledKey: "1", DemoMode.routeKey: "not json"]

        let demo = DemoMode.from(environment: environment)

        XCTAssertNotNil(demo)
        XCTAssertNil(demo?.routerSnapshot)
        XCTAssertNil(demo?.seedURL)
    }

    func test_startingRoute_withSeededListName_opensThatListOnLibrary() {
        let list = LibraryList(id: UUID(), name: "Best of 2026", segment: .moviesAndTV, system: nil, sort: .dateAdded, position: 0)
        let demo = DemoMode(
            seedURL: nil,
            routerSnapshot: RouterSnapshot(selectedTab: .browse),
            openListName: "Best of 2026"
        )

        let route = demo.startingRoute(in: LibrarySnapshot(lists: [list], entries: []))

        XCTAssertEqual(route, RouterSnapshot(selectedTab: .library, favoritesPath: [.libraryList(id: list.id)]))
    }

    func test_startingRoute_withUnknownListName_keepsRequestedRoute() {
        let requested = RouterSnapshot(selectedTab: .search)
        let demo = DemoMode(seedURL: nil, routerSnapshot: requested, openListName: "Missing")

        XCTAssertEqual(demo.startingRoute(in: LibrarySnapshot(lists: [], entries: [])), requested)
    }

    /// The capture scripts write routes by hand, so the JSON shape is a contract.
    func test_routerSnapshot_encodesRoutesInTheShapeCaptureScriptsWrite() throws {
        let snapshot = RouterSnapshot(
            selectedTab: .browse,
            browsePath: [.tvSeries(id: 95396), .awardFamily(.academy), .person(id: 27319)]
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        let path = json?["browsePath"] as? [[String: [String: Any]]]

        XCTAssertEqual(json?["selectedTab"] as? String, "browse")
        XCTAssertEqual(path?[0]["tvSeries"]?["id"] as? Int, 95396)
        XCTAssertEqual(path?[1]["awardFamily"]?["_0"] as? String, "academy")
        XCTAssertEqual(path?[2]["person"]?["id"] as? Int, 27319)
    }

    func test_seedDecode_readsLibraryObjectAndDefaultsMissingSections() throws {
        let data = Data(
            #"""
            {"shots": [], "library": {"watched": [
                {"id": 550, "kind": "movie", "title": "Fight Club", "releaseDate": "1999-10-15", "score": 9}
            ]}}
            """#.utf8
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let seed = try DemoLibrarySeed.load(from: url)

        XCTAssertEqual(seed.watched.map(\.id), [550])
        XCTAssertEqual(seed.watched.first?.draft.releaseDate, ISO8601DateFormatter().date(from: "1999-10-15T00:00:00Z"))
        XCTAssertTrue(seed.watchlist.isEmpty)
        XCTAssertTrue(seed.lists.isEmpty)
    }

    func test_apply_putsWatchedNewestFirstAndWatchlistInFileOrder() async throws {
        let lists = await ListsRepository.empty()
        let seed = DemoLibrarySeed(
            watched: [Self.item(1, .movie), Self.item(2, .tv)],
            watchlist: [Self.item(3, .movie), Self.item(4, .movie)]
        )

        try await seed.apply(lists: lists, annotations: .empty(), now: now)

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let watchlist = try XCTUnwrap(snapshot.list(.watchlist))
        XCTAssertEqual(LibraryOrdering.displayed(Self.entries(snapshot, watched), list: watched).map(\.itemID), [1, 2])
        XCTAssertEqual(LibraryOrdering.displayed(Self.entries(snapshot, watchlist), list: watchlist).map(\.itemID), [3, 4])
    }

    func test_apply_customListKeepsFileOrderTopToBottom() async throws {
        let lists = await ListsRepository.empty()
        let seed = DemoLibrarySeed(
            lists: [.init(name: "Best of the Year", items: [Self.item(7, .movie), Self.item(8, .tv), Self.item(9, .movie)])]
        )

        try await seed.apply(lists: lists, annotations: .empty(), now: now)

        let snapshot = try await lists.snapshot()
        let custom = try XCTUnwrap(snapshot.lists.first { $0.name == "Best of the Year" })
        XCTAssertEqual(custom.segment, .moviesAndTV)
        XCTAssertEqual(LibraryOrdering.displayed(Self.entries(snapshot, custom), list: custom).map(\.itemID), [7, 8, 9])
    }

    func test_apply_savesScoresAndNotesForMoviesAndSeries() async throws {
        let annotations = AnnotationsRepository.empty()
        let seed = DemoLibrarySeed(
            watched: [
                Self.item(1, .movie, score: 9.5, note: "Perfect ending."),
                Self.item(2, .tv, score: 8),
                Self.item(3, .movie),
            ]
        )

        try await seed.apply(lists: await ListsRepository.empty(), annotations: annotations, now: now)

        let movie = try await annotations.annotation(for: .movie(1))
        let series = try await annotations.annotation(for: .series(2))
        let unrated = try await annotations.annotation(for: .movie(3))
        XCTAssertEqual(movie?.score, 9.5)
        XCTAssertEqual(movie?.note, "Perfect ending.")
        XCTAssertEqual(series?.score, 8)
        XCTAssertNil(series?.note)
        XCTAssertNil(unrated)
    }

    private static func item(
        _ id: Int,
        _ kind: ListItemKind,
        score: Double? = nil,
        note: String? = nil
    ) -> DemoLibrarySeed.Item {
        DemoLibrarySeed.Item(
            id: id,
            kind: kind,
            title: "Title \(id)",
            posterPath: nil,
            releaseDate: nil,
            genres: nil,
            voteAverage: nil,
            popularity: nil,
            score: score,
            note: note
        )
    }

    private static func entries(_ snapshot: LibrarySnapshot, _ list: LibraryList) -> [ListEntry] {
        snapshot.entries.filter { $0.listID == list.id }
    }
}
