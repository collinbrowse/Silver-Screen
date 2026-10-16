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

    func test_migrate_fromV1_appliesLaterVersionsAndKeepsRows() async throws {
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
        XCTAssertEqual(version, LibrarySchema.currentVersion)
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

    func test_migrate_fromV2_keepsRowsAndBackfillsCreationDates() async throws {
        let fixture = try SQLiteDatabase(fileURL: databaseURL())
        try fixture.execute("BEGIN IMMEDIATE;")
        for statement in LibrarySchema.v1Statements + LibrarySchema.v2Statements {
            try fixture.execute(statement)
        }
        try fixture.execute(
            """
            INSERT INTO schema_migrations (version, applied_at) VALUES
              (1, '2020-01-01T00:00:00.000Z'), (2, '2020-01-01T00:00:00.000Z');
            INSERT INTO library_list
              (id, name, segment, system_kind, sort, position, updated_at, revision, deleted_at)
            VALUES
              ('L1', 'Watched', 'moviesAndTV', 'watched', 'dateAdded', 0, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('L2', 'Empty', 'moviesAndTV', NULL, 'dateAdded', 1, '2026-10-02T00:00:00.000Z', 1, NULL);
            INSERT INTO media_item
              (item_key, tmdb_id, kind, title, genre_names_json, vote_average, popularity,
               updated_at, revision, deleted_at)
            VALUES
              ('movie-550', 550, 'movie', 'Fight Club', '[]', 8.4, 40, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('movie-600', 600, 'movie', 'Other', '[]', 7, 10, '2026-10-01T00:00:00.000Z', 1, NULL);
            INSERT INTO list_membership
              (id, list_id, item_key, added_at, position, updated_at, revision, deleted_at)
            VALUES
              ('M1', 'L1', 'movie-550', '2024-03-01T00:00:00.000Z', 0, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('M2', 'L1', 'movie-600', '2025-05-01T00:00:00.000Z', 1, '2026-10-01T00:00:00.000Z', 1, NULL);
            INSERT INTO annotation
              (id, item_key, kind, subject_id, season_number, episode_number,
               score, note, watched_at, updated_at, revision, deleted_at)
            VALUES
              ('A1', 'movie-550-0-0', 'movie', 550, 0, 0, 8, NULL,
               '2023-07-04T00:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL),
              ('A2', 'movie-600-0-0', 'movie', 600, 0, 0, 7, NULL,
               NULL, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('A3', 'movie-700-0-0', 'movie', 700, 0, 0, 6, NULL,
               NULL, '2026-10-03T00:00:00.000Z', 1, NULL),
              ('A4', 'tvEpisode-42-1-1', 'tvEpisode', 42, 1, 1, 9, NULL,
               '2025-01-15T00:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL);
            INSERT INTO tv_series_watch
              (series_id, next_up_season, next_up_episode, updated_at, revision, deleted_at)
            VALUES (42, 1, 3, '2026-09-01T00:00:00.000Z', 1, NULL);
            INSERT INTO tv_episode_completed (series_id, season_number, episode_number)
            VALUES (42, 1, 1), (42, 1, 2);
            """
        )
        try fixture.execute("COMMIT;")
        fixture.close()

        let store = try makeStore()
        try await store.bootstrap()

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT MAX(version) FROM schema_migrations;"), 3)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM library_list;"), 2)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM media_item;"), 2)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM list_membership;"), 2)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM annotation;"), 4)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM tv_series_watch;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM tv_episode_completed;"), 2)

        // Lists take their earliest item's added date, else their last update.
        XCTAssertEqual(
            try db.scalarText("SELECT created_at FROM library_list WHERE id = 'L1';"),
            "2024-03-01T00:00:00.000Z"
        )
        XCTAssertEqual(
            try db.scalarText("SELECT created_at FROM library_list WHERE id = 'L2';"),
            "2026-10-02T00:00:00.000Z"
        )
        // Annotations prefer watched date, then the title's list added date, then last update.
        XCTAssertEqual(
            try db.scalarText("SELECT created_at FROM annotation WHERE id = 'A1';"),
            "2023-07-04T00:00:00.000Z"
        )
        XCTAssertEqual(
            try db.scalarText("SELECT created_at FROM annotation WHERE id = 'A2';"),
            "2025-05-01T00:00:00.000Z"
        )
        XCTAssertEqual(
            try db.scalarText("SELECT created_at FROM annotation WHERE id = 'A3';"),
            "2026-10-03T00:00:00.000Z"
        )
        // Episodes prefer the episode's watched date, then the series' last update.
        XCTAssertEqual(
            try db.scalarText(
                """
                SELECT completed_at FROM tv_episode_completed
                WHERE series_id = 42 AND season_number = 1 AND episode_number = 1;
                """
            ),
            "2025-01-15T00:00:00.000Z"
        )
        XCTAssertEqual(
            try db.scalarText(
                """
                SELECT completed_at FROM tv_episode_completed
                WHERE series_id = 42 AND season_number = 1 AND episode_number = 2;
                """
            ),
            "2026-09-01T00:00:00.000Z"
        )
        XCTAssertEqual(
            try db.scalarInt(
                """
                SELECT COUNT(*) FROM tv_episode_completed
                WHERE updated_at IS NULL OR revision != 1 OR deleted_at IS NOT NULL;
                """
            ),
            0
        )

        let tv = try await store.fetchTVWatchStates()
        XCTAssertEqual(tv.first?.completed.count, 2)
    }

    func test_replaceAnnotations_savingOneRating_leavesOtherRowsUntouched() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let other = MediaAnnotation(key: .movie(1), score: 7, note: "Fine", watchedAt: nil)
        let rated = MediaAnnotation(key: .movie(2), score: 6, note: nil, watchedAt: nil)
        try await store.apply(.replaceAnnotations([other, rated]))
        try backdateAnnotations()

        let rerated = MediaAnnotation(key: .movie(2), score: 9, note: nil, watchedAt: nil)
        try await store.apply(.replaceAnnotations([other, rerated]))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(
            try db.scalarText("SELECT updated_at FROM annotation WHERE subject_id = 1;"),
            Self.oldDate
        )
        XCTAssertEqual(try db.scalarInt("SELECT revision FROM annotation WHERE subject_id = 1;"), 1)
    }

    func test_replaceAnnotations_changedRow_bumpsRevisionAndKeepsCreatedAt() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        try await store.apply(
            .replaceAnnotations([MediaAnnotation(key: .movie(2), score: 6, note: nil, watchedAt: nil)])
        )
        try backdateAnnotations()

        try await store.apply(
            .replaceAnnotations([MediaAnnotation(key: .movie(2), score: 9, note: nil, watchedAt: nil)])
        )

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT revision FROM annotation WHERE subject_id = 2;"), 2)
        XCTAssertNotEqual(
            try db.scalarText("SELECT updated_at FROM annotation WHERE subject_id = 2;"),
            Self.oldDate
        )
        XCTAssertEqual(
            try db.scalarText("SELECT created_at FROM annotation WHERE subject_id = 2;"),
            Self.oldDate
        )
        let annotations = try await store.fetchAnnotations()
        XCTAssertEqual(annotations.first?.score, 9)
    }

    func test_replaceLists_unchangedSnapshot_keepsRevision() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watched)
        let snapshot = LibrarySnapshot(lists: [list], entries: [entry(550, in: list)])
        try await store.apply(.replaceLists(snapshot))
        try await store.apply(.replaceLists(snapshot))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM library_list;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM media_item;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM list_membership;"), 1)
    }

    func test_replaceLists_removedItem_leavesTombstoneAndHidesItem() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watchlist)
        let kept = entry(1, in: list)
        let removed = entry(2, in: list, position: 1)
        try await store.apply(.replaceLists(LibrarySnapshot(lists: [list], entries: [kept, removed])))

        try await store.apply(.replaceLists(LibrarySnapshot(lists: [list], entries: [kept])))

        let snapshot = try await store.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.map(\.itemKey), [kept.itemKey])
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(
            try db.scalarInt(
                """
                SELECT COUNT(*) FROM list_membership
                WHERE item_key = 'movie-2' AND deleted_at IS NOT NULL AND revision = 2;
                """
            ),
            1
        )
        XCTAssertEqual(
            try db.scalarInt(
                "SELECT revision FROM list_membership WHERE item_key = 'movie-1';"
            ),
            1
        )
    }

    func test_replaceLists_reAddedItem_revivesTombstonedRow() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watchlist)
        let item = entry(2, in: list)
        try await store.apply(.replaceLists(LibrarySnapshot(lists: [list], entries: [item])))
        try await store.apply(.replaceLists(LibrarySnapshot(lists: [list], entries: [])))

        try await store.apply(.replaceLists(LibrarySnapshot(lists: [list], entries: [item])))

        let snapshot = try await store.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.map(\.itemKey), [item.itemKey])
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM list_membership;"), 1)
        XCTAssertEqual(
            try db.scalarInt("SELECT revision FROM list_membership WHERE deleted_at IS NULL;"),
            3
        )
        XCTAssertEqual(
            try db.scalarInt("SELECT COUNT(*) FROM media_item WHERE deleted_at IS NULL;"),
            1
        )
    }

    func test_replaceTVWatch_unmarkedEpisode_leavesTombstoneAndCanBeRemarked() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let episode1 = TVEpisodeRef(seasonNumber: 1, episodeNumber: 1)
        let episode2 = TVEpisodeRef(seasonNumber: 1, episodeNumber: 2)
        func state(_ completed: [TVEpisodeRef]) -> TVSeriesWatchState {
            TVSeriesWatchState(
                seriesID: 42,
                completed: completed,
                nextUp: nil,
                nextUpTitle: nil,
                catalogSnapshot: nil
            )
        }
        try await store.apply(.replaceTVWatch([state([episode1, episode2])]))
        try await store.apply(.replaceTVWatch([state([episode1])]))

        var tv = try await store.fetchTVWatchStates()
        XCTAssertEqual(tv.first?.completed, [episode1])
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(
            try db.scalarInt(
                """
                SELECT COUNT(*) FROM tv_episode_completed
                WHERE episode_number = 2 AND deleted_at IS NOT NULL AND revision = 2;
                """
            ),
            1
        )

        try await store.apply(.replaceTVWatch([state([episode1, episode2])]))

        tv = try await store.fetchTVWatchStates()
        XCTAssertEqual(tv.first?.completed, [episode1, episode2])
        XCTAssertEqual(
            try db.scalarInt(
                "SELECT revision FROM tv_episode_completed WHERE episode_number = 2 AND deleted_at IS NULL;"
            ),
            3
        )
        XCTAssertEqual(
            try db.scalarInt("SELECT revision FROM tv_episode_completed WHERE episode_number = 1;"),
            1
        )
    }

    func test_countRatings_withoutCutoff_countsEveryLiveScore() async throws {
        let store = try makeStore()
        try await store.apply(.replaceAnnotations([
            MediaAnnotation(key: .movie(1), score: 8, note: nil, watchedAt: nil),
            MediaAnnotation(key: .series(2), score: 7, note: nil, watchedAt: nil),
            MediaAnnotation(key: .movie(3), score: nil, note: "Note only", watchedAt: nil),
            MediaAnnotation(key: .movie(4), score: 6, note: nil, watchedAt: nil),
        ]))
        try await store.apply(.replaceAnnotations([
            MediaAnnotation(key: .movie(1), score: 8, note: nil, watchedAt: nil),
            MediaAnnotation(key: .series(2), score: 7, note: nil, watchedAt: nil),
            MediaAnnotation(key: .movie(3), score: nil, note: "Note only", watchedAt: nil),
        ]))

        let count = try await store.countRatings(createdAfter: nil)

        XCTAssertEqual(count, 2)
    }

    func test_countRatings_withCutoff_skipsRatingsCreatedBefore() async throws {
        let store = try makeStore()
        try await store.apply(.replaceAnnotations([
            MediaAnnotation(key: .movie(1), score: 8, note: nil, watchedAt: nil),
            MediaAnnotation(key: .movie(2), score: 7, note: nil, watchedAt: nil),
        ]))
        try backdateAnnotations()
        try await store.apply(.replaceAnnotations([
            MediaAnnotation(key: .movie(1), score: 9, note: nil, watchedAt: nil),
            MediaAnnotation(key: .movie(2), score: 7, note: nil, watchedAt: nil),
            MediaAnnotation(key: .movie(3), score: 6, note: nil, watchedAt: nil),
        ]))

        let count = try await store.countRatings(
            createdAfter: try XCTUnwrap(LibrarySQLDate.decode("2021-01-01T00:00:00.000Z"))
        )

        XCTAssertEqual(count, 1, "Editing movie 1 keeps its old created_at; only movie 3 is new")
    }

    private static let oldDate = "2020-01-01T00:00:00.000Z"

    /// Moves every annotation's dates into the past, so a later write that touched a
    /// row is visible even within the same millisecond.
    private func backdateAnnotations() throws {
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        try db.execute(
            "UPDATE annotation SET updated_at = '\(Self.oldDate)', created_at = '\(Self.oldDate)';"
        )
    }

    private func entry(_ id: Int, in list: LibraryList, position: Int = 0) -> ListEntry {
        ListEntry(
            listID: list.id,
            draft: ListItemDraft(
                id: id,
                kind: .movie,
                title: "Movie \(id)",
                imagePath: nil,
                releaseDate: nil,
                genreNames: ["Drama"],
                voteAverage: 7,
                popularity: 10
            ),
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            position: position
        )
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
