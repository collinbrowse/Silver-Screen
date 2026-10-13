//
//  SQLiteLibraryStoreTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class SQLiteLibraryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func test_bootstrap_appliesCurrentSchemaVersion() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        let version = try db.scalarInt("SELECT MAX(version) FROM schema_migrations;")
        XCTAssertEqual(version, LibrarySchema.currentVersion)
    }

    func test_bootstrap_freshInstall_stampsJsonImportNone() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        let stamp = try db.scalarText(
            "SELECT value FROM sync_state WHERE key = 'json_import';"
        )
        XCTAssertEqual(stamp, "none")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("lists.json").path
            )
        )
    }

    func test_migrate_fromV1_appliesV2AndKeepsRows() async throws {
        let fixture = try SQLiteDatabase(fileURL: databaseURL())
        try fixture.execute("BEGIN IMMEDIATE;")
        for statement in LibrarySchema.v1Statements {
            try fixture.execute(statement)
        }
        try fixture.run(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (1, ?);"
        ) { statement in
            SQLiteBinding.text(statement, index: 1, "2020-01-01T00:00:00.000Z")
        }
        try fixture.run(
            """
            INSERT INTO media_item
              (item_key, tmdb_id, kind, title, image_path, release_date,
               genre_names_json, vote_average, popularity, updated_at, revision, deleted_at)
            VALUES ('movie-550', 550, 'movie', 'Fight Club', NULL, NULL, '[]', 8.4, 40, ?, 1, NULL);
            """
        ) { statement in
            SQLiteBinding.text(statement, index: 1, "2020-01-01T00:00:00.000Z")
        }
        try fixture.execute("COMMIT;")
        fixture.close()

        let store = try makeStore()
        try await store.bootstrap()

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        let version = try db.scalarInt("SELECT MAX(version) FROM schema_migrations;")
        XCTAssertEqual(version, 2)
        let title = try db.scalarText(
            "SELECT title FROM media_item WHERE item_key = 'movie-550';"
        )
        XCTAssertEqual(title, "Fight Club")
        let indexCount = try db.scalarInt(
            """
            SELECT COUNT(*) FROM sqlite_master
            WHERE type = 'index' AND name = 'media_item_kind_popularity';
            """
        )
        XCTAssertEqual(indexCount, 1)
    }

    func test_replaceLists_doesNotClearAnnotations() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let annotation = MediaAnnotation(
            key: .movie(550),
            score: 8,
            note: "Classic",
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await store.apply(.replaceAnnotations([annotation]))

        let list = LibraryList.system(.watched)
        let draft = ListItemDraft(
            id: 550,
            kind: .movie,
            title: "Fight Club",
            imagePath: "/p.jpg",
            releaseDate: nil,
            genreNames: ["Drama"],
            voteAverage: 8.4,
            popularity: 40
        )
        let entry = ListEntry(listID: list.id, draft: draft, addedAt: Date(), position: 0)
        try await store.apply(
            .replaceLists(LibrarySnapshot(lists: [list], entries: [entry]))
        )

        let annotations = try await store.fetchAnnotations()
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.key, .movie(550))
        let snapshot = try await store.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries.first?.title, "Fight Club")
    }

    func test_replaceAnnotations_doesNotClearLists() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watched)
        let draft = ListItemDraft(
            id: 550,
            kind: .movie,
            title: "Fight Club",
            imagePath: "/p.jpg",
            releaseDate: nil,
            genreNames: ["Drama"],
            voteAverage: 8.4,
            popularity: 40
        )
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(
                    lists: [list],
                    entries: [ListEntry(listID: list.id, draft: draft, addedAt: Date(), position: 0)]
                )
            )
        )
        try await store.apply(
            .replaceAnnotations([
                MediaAnnotation(
                    key: .movie(550),
                    score: 8,
                    note: "Classic",
                    watchedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ])
        )

        let snapshot = try await store.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.first?.title, "Fight Club")
        let annotations = try await store.fetchAnnotations()
        XCTAssertEqual(annotations.count, 1)
    }

    func test_replaceTVWatch_doesNotClearLists() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watched)
        let draft = ListItemDraft(
            id: 550,
            kind: .movie,
            title: "Fight Club",
            imagePath: "/p.jpg",
            releaseDate: nil,
            genreNames: ["Drama"],
            voteAverage: 8.4,
            popularity: 40
        )
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(
                    lists: [list],
                    entries: [ListEntry(listID: list.id, draft: draft, addedAt: Date(), position: 0)]
                )
            )
        )
        try await store.apply(
            .replaceTVWatch([
                TVSeriesWatchState(
                    seriesID: 42,
                    completed: [TVEpisodeRef(seasonNumber: 1, episodeNumber: 1)],
                    nextUp: TVEpisodeRef(seasonNumber: 1, episodeNumber: 2),
                    nextUpTitle: "Ep 2",
                    catalogSnapshot: nil
                )
            ])
        )

        let snapshot = try await store.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.first?.title, "Fight Club")
        let tv = try await store.fetchTVWatchStates()
        XCTAssertEqual(tv.first?.seriesID, 42)
    }

    func test_importLegacyJSON_thenPreferSQLite() async throws {
        let listsURL = directory.appendingPathComponent("lists.json")
        let annotationsURL = directory.appendingPathComponent("annotations.json")
        let tvURL = directory.appendingPathComponent("tv-progress.json")

        let list = LibraryList.system(.watchlist)
        let draft = ListItemDraft(
            id: 100,
            kind: .movie,
            title: "Imported",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let snapshot = LibrarySnapshot(
            lists: [list],
            entries: [ListEntry(listID: list.id, draft: draft, addedAt: Date(), position: 0)]
        )
        let fileLists = FileListsStore(fileURL: listsURL)
        try await fileLists.save(snapshot)

        let fileAnnotations = FileAnnotationsStore(fileURL: annotationsURL)
        try await fileAnnotations.save([
            MediaAnnotation(key: .movie(100), score: 7, note: nil, watchedAt: Date())
        ])

        let fileTV = FileTVWatchStore(fileURL: tvURL)
        try await fileTV.save([
            TVSeriesWatchState(
                seriesID: 42,
                completed: [TVEpisodeRef(seasonNumber: 1, episodeNumber: 1)],
                nextUp: TVEpisodeRef(seasonNumber: 1, episodeNumber: 2),
                nextUpTitle: "Ep 2",
                catalogSnapshot: nil
            )
        ])

        let store = try SQLiteLibraryStore(
            databaseURL: databaseURL(),
            listsJSONURL: listsURL,
            annotationsJSONURL: annotationsURL,
            tvWatchJSONURL: tvURL
        )
        try await store.bootstrap()

        let loaded = try await store.fetchSnapshot()
        XCTAssertEqual(loaded.entries.first?.title, "Imported")
        let importedAnnotations = try await store.fetchAnnotations()
        XCTAssertEqual(importedAnnotations.count, 1)
        let importedTV = try await store.fetchTVWatchStates()
        XCTAssertEqual(importedTV.first?.seriesID, 42)

        XCTAssertFalse(FileManager.default.fileExists(atPath: listsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: listsURL.appendingPathExtension("imported").path))

        // Second bootstrap with fresh JSON must prefer existing SQLite rows.
        try await fileLists.save(
            LibrarySnapshot(
                lists: [list],
                entries: [
                    ListEntry(
                        listID: list.id,
                        draft: ListItemDraft(
                            id: 999,
                            kind: .movie,
                            title: "Should Not Win",
                            imagePath: nil,
                            releaseDate: nil,
                            genreNames: [],
                            voteAverage: 0,
                            popularity: 0
                        ),
                        addedAt: Date(),
                        position: 0
                    )
                ]
            )
        )
        // Import stamp already set — recreate store against same DB.
        let storeAgain = try SQLiteLibraryStore(
            databaseURL: databaseURL(),
            listsJSONURL: listsURL,
            annotationsJSONURL: annotationsURL,
            tvWatchJSONURL: tvURL
        )
        try await storeAgain.bootstrap()
        let again = try await storeAgain.fetchSnapshot()
        XCTAssertEqual(again.entries.first?.title, "Imported")
    }

    func test_importLegacyJSON_fillsEmptyDomainsWhenStampMissing() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watchlist)
        let draft = ListItemDraft(
            id: 100,
            kind: .movie,
            title: "Kept List",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(
                    lists: [list],
                    entries: [ListEntry(listID: list.id, draft: draft, addedAt: Date(), position: 0)]
                )
            )
        )

        let inspect = try SQLiteDatabase(fileURL: databaseURL())
        try inspect.execute("DELETE FROM sync_state WHERE key = 'json_import';")
        inspect.close()

        let annotationsURL = directory.appendingPathComponent("annotations.json")
        let fileAnnotations = FileAnnotationsStore(fileURL: annotationsURL)
        try await fileAnnotations.save([
            MediaAnnotation(key: .movie(100), score: 7, note: nil, watchedAt: Date())
        ])
        let tvURL = directory.appendingPathComponent("tv-progress.json")
        let fileTV = FileTVWatchStore(fileURL: tvURL)
        try await fileTV.save([
            TVSeriesWatchState(
                seriesID: 42,
                completed: [TVEpisodeRef(seasonNumber: 1, episodeNumber: 1)],
                nextUp: nil,
                nextUpTitle: nil,
                catalogSnapshot: nil
            )
        ])

        let storeAgain = try makeStore()
        try await storeAgain.bootstrap()

        let snapshot = try await storeAgain.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.first?.title, "Kept List")
        let annotations = try await storeAgain.fetchAnnotations()
        XCTAssertEqual(annotations.first?.key, .movie(100))
        let tv = try await storeAgain.fetchTVWatchStates()
        XCTAssertEqual(tv.first?.seriesID, 42)
        XCTAssertFalse(FileManager.default.fileExists(atPath: annotationsURL.path))
    }

    func test_adapters_roundTripThroughSharedStore() async throws {
        let library = try makeStore()
        try await library.bootstrap()
        let lists = LibraryListsStoreAdapter(library: library)
        let annotations = LibraryAnnotationsStoreAdapter(library: library)
        let tvWatch = LibraryTVWatchStoreAdapter(library: library)

        let list = LibraryList.system(.watched)
        let draft = ListItemDraft(
            id: 1,
            kind: .movie,
            title: "One",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 1,
            popularity: 1
        )
        try await lists.save(
            LibrarySnapshot(
                lists: [list],
                entries: [ListEntry(listID: list.id, draft: draft, addedAt: Date(), position: 0)]
            )
        )
        try await annotations.save([
            MediaAnnotation(key: .movie(1), score: 9, note: "Great", watchedAt: Date())
        ])
        try await tvWatch.save([
            TVSeriesWatchState(seriesID: 7, completed: [], nextUp: nil, nextUpTitle: nil, catalogSnapshot: nil)
        ])

        let listRows = try await lists.load()
        XCTAssertEqual(listRows.entries.count, 1)
        let annotationRows = try await annotations.load()
        XCTAssertEqual(annotationRows.first?.score, 9)
        let tvRows = try await tvWatch.load()
        XCTAssertEqual(tvRows.first?.seriesID, 7)
    }

    @MainActor
    func test_listsRepository_toggleWatched_throughSQLiteAdapters() async throws {
        let library = try makeStore()
        try await library.bootstrap()
        let lists = ListsRepository(
            store: LibraryListsStoreAdapter(library: library),
            logger: SilentLogger()
        )
        let draft = ListItemDraft(
            id: 550,
            kind: .movie,
            title: "Fight Club",
            imagePath: "/p.jpg",
            releaseDate: Date(timeIntervalSince1970: 900_000_000),
            genreNames: ["Drama", "Thriller"],
            voteAverage: 8.4,
            popularity: 40
        )
        let added = try await lists.toggleWatched(draft)
        XCTAssertEqual(added.action, .added)
        let snapshot = try await lists.snapshot()
        XCTAssertTrue(snapshot.entries.contains(where: { $0.itemKey == draft.itemKey }))
        let removed = try await lists.toggleWatched(draft)
        XCTAssertEqual(removed.action, .removed)
    }

    private func databaseURL() -> URL {
        directory.appendingPathComponent("library.sqlite")
    }

    private func makeStore() throws -> SQLiteLibraryStore {
        try SQLiteLibraryStore(
            databaseURL: databaseURL(),
            listsJSONURL: directory.appendingPathComponent("lists.json"),
            annotationsJSONURL: directory.appendingPathComponent("annotations.json"),
            tvWatchJSONURL: directory.appendingPathComponent("tv-progress.json")
        )
    }
}
