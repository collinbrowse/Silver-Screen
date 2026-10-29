//
//  DiaryStoreTests.swift
//  SilverScreenTests
//
//  Schema v4 (diary_entry) on a real library.sqlite in a temp directory: the v3 to v4
//  upgrade and its backfill, and the diffed diary writes.
//

import XCTest
@testable import SilverScreen

final class DiaryStoreTests: XCTestCase {
    private static let oldDate = "2020-01-01T00:00:00.000Z"
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - v3 → v4

    func test_migrate_fromV3_keepsEveryRow() async throws {
        try writeV3Fixture()

        let store = try makeStore()
        try await store.bootstrap()

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT MAX(version) FROM schema_migrations;"), LibrarySchema.currentVersion)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM library_list;"), 2)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM media_item;"), 5)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM list_membership;"), 5)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM annotation;"), 3)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM tv_series_watch;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM tv_episode_completed;"), 1)
        // Existing rows keep their sync metadata; the migration is not a write to them.
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM annotation;"), 1)
        XCTAssertEqual(
            try db.scalarText("SELECT updated_at FROM annotation WHERE id = 'A1';"),
            "2026-10-01T00:00:00.000Z"
        )
    }

    func test_migrate_fromV3_backfillsOneEntryPerLiveWatchedTitle() async throws {
        try writeV3Fixture()

        let store = try makeStore()
        try await store.bootstrap()

        let entries = try await store.fetchDiaryEntries()
        // movie-550, movie-600, tv-42 are on Watched. movie-700 is only on Watchlist,
        // and movie-800's Watched row is a tombstone.
        XCTAssertEqual(Set(entries.map(\.subject)), [.movie(550), .movie(600), .series(42)])
        XCTAssertEqual(
            Set(entries.map(\.id)),
            Set([DiarySubject.movie(550), .movie(600), .series(42)].map(SQLiteLibraryStore.backfilledDiaryID))
        )
        XCTAssertTrue(entries.allSatisfy { !$0.isRewatch })
    }

    func test_migrate_fromV3_backfillUsesEarliestOfRatingAndWatchedDates() async throws {
        try writeV3Fixture()

        let store = try makeStore()
        try await store.bootstrap()

        let entries = try await store.fetchDiaryEntries()
        let bySubject = Dictionary(uniqueKeysWithValues: entries.map { ($0.subject, $0) })
        // Rated (2023-07-04) before it joined Watched (2024-03-01): the rating date wins.
        let fightClub = try XCTUnwrap(bySubject[.movie(550)])
        XCTAssertEqual(fightClub.watchedOn, DiaryDay(date("2023-07-04T12:00:00.000Z")))
        XCTAssertEqual(fightClub.loggedAt, date("2023-07-04T12:00:00.000Z"))
        // No rating: the day it joined Watched.
        XCTAssertEqual(bySubject[.movie(600)]?.watchedOn, DiaryDay(date("2025-05-01T12:00:00.000Z")))
        // Joined Watched (2025-02-01) before the series was rated (2025-06-01).
        XCTAssertEqual(bySubject[.series(42)]?.watchedOn, DiaryDay(date("2025-02-01T12:00:00.000Z")))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        let createdAt = try db.scalarText(
            "SELECT created_at FROM diary_entry WHERE tmdb_id = 550;"
        )
        XCTAssertEqual(createdAt, "2023-07-04T12:00:00.000Z")
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM diary_entry;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM diary_entry WHERE deleted_at IS NOT NULL;"), 0)
    }

    func test_migrate_fromV3_backfillCopiesRatingReviewAndTitleSnapshot() async throws {
        try writeV3Fixture()

        let store = try makeStore()
        try await store.bootstrap()

        let entries = try await store.fetchDiaryEntries()
        let fightClub = try XCTUnwrap(entries.first { $0.subject == .movie(550) })
        XCTAssertEqual(fightClub.title, "Fight Club")
        XCTAssertEqual(fightClub.releaseYear, 1999)
        XCTAssertEqual(fightClub.posterPath, "/fc.jpg")
        XCTAssertEqual(fightClub.score, 8)
        XCTAssertEqual(fightClub.review, "Rules.")
        let other = try XCTUnwrap(entries.first { $0.subject == .movie(600) })
        XCTAssertNil(other.score)
        XCTAssertNil(other.review)
        XCTAssertNil(other.releaseYear)
        // The series takes the series rating, not an episode's.
        XCTAssertEqual(entries.first { $0.subject == .series(42) }?.score, 9)
    }

    func test_bootstrap_freshInstall_createsEmptyDiary() async throws {
        let store = try makeStore()
        try await store.bootstrap()

        let entries = try await store.fetchDiaryEntries()

        XCTAssertTrue(entries.isEmpty)
    }

    func test_importLegacyJSON_backfillsDiaryForImportedWatchedTitles() async throws {
        let watched = LibraryList.system(.watched)
        let addedAt = date("2024-08-10T12:00:00.000Z")
        try await FileListsStore(fileURL: directory.appendingPathComponent("lists.json")).save(
            LibrarySnapshot(
                lists: [watched],
                entries: [ListEntry(listID: watched.id, draft: draft(550), addedAt: addedAt, position: 0)]
            )
        )

        let store = try makeStore()
        try await store.bootstrap()

        let entries = try await store.fetchDiaryEntries()
        XCTAssertEqual(entries.map(\.subject), [.movie(550)])
        XCTAssertEqual(entries.first?.watchedOn, DiaryDay(addedAt))
    }

    func test_backfillNow_addsEntriesForWatchedAndNeverDuplicates() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let watched = LibraryList.system(.watched)
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(
                    lists: [watched],
                    entries: [ListEntry(listID: watched.id, draft: draft(550), addedAt: Date(), position: 0)]
                )
            )
        )

        try await store.backfillDiaryFromWatchedNow()
        try await store.backfillDiaryFromWatchedNow()

        let entries = try await store.fetchDiaryEntries()
        XCTAssertEqual(entries.map(\.id), [SQLiteLibraryStore.backfilledDiaryID(for: .movie(550))])
    }

    func test_backfillNow_doesNotReviveDeletedEntry() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let watched = LibraryList.system(.watched)
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(
                    lists: [watched],
                    entries: [ListEntry(listID: watched.id, draft: draft(550), addedAt: Date(), position: 0)]
                )
            )
        )
        try await store.backfillDiaryFromWatchedNow()
        try await store.apply(.replaceDiary([]))

        try await store.backfillDiaryFromWatchedNow()

        let entries = try await store.fetchDiaryEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Diffed writes

    func test_replaceDiary_roundTripsEveryField() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let entry = makeEntry(
            subject: .series(42),
            watchedOn: DiaryDay(year: 2026, month: 10, day: 16),
            score: 7.5,
            review: "Better the second time.",
            isRewatch: true
        )

        try await store.apply(.replaceDiary([entry]))

        let loaded = try await store.fetchDiaryEntries()
        XCTAssertEqual(loaded, [entry])
    }

    func test_fetchEpisodeWatches_joinsSeriesTitleAndSkipsUnmarkedEpisodes() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.inProgress)
        let series = ListItemDraft(
            id: 42,
            kind: .tv,
            title: "Severance",
            imagePath: "/sev.jpg",
            releaseDate: nil,
            genreNames: [],
            voteAverage: 8,
            popularity: 10
        )
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(lists: [list], entries: [ListEntry(listID: list.id, draft: series, addedAt: Date(), position: 0)])
            )
        )
        let first = TVEpisodeRef(seasonNumber: 1, episodeNumber: 1)
        let second = TVEpisodeRef(seasonNumber: 1, episodeNumber: 2)
        try await store.apply(.replaceTVWatch([TVSeriesWatchState(seriesID: 42, completed: [first, second])]))
        try await store.apply(.replaceTVWatch([TVSeriesWatchState(seriesID: 42, completed: [first])]))
        // An episode of a series with no stored title has nothing to show.
        try await store.apply(
            .replaceTVWatch([
                TVSeriesWatchState(seriesID: 42, completed: [first]),
                TVSeriesWatchState(seriesID: 99, completed: [first]),
            ])
        )

        let watches = try await store.fetchEpisodeWatches()

        XCTAssertEqual(watches.map(\.seriesID), [42])
        XCTAssertEqual(watches.first?.seriesTitle, "Severance")
        XCTAssertEqual(watches.first?.posterPath, "/sev.jpg")
        XCTAssertEqual(watches.first?.episode, first)
        let narrowed = try await store.fetchEpisodeWatches(seriesID: 42)
        XCTAssertEqual(narrowed, watches)
        let other = try await store.fetchEpisodeWatches(seriesID: 7)
        XCTAssertEqual(other, [])
    }

    func test_replaceDiary_savingOneEntry_leavesOtherRowsUntouched() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let other = makeEntry(subject: .movie(1), score: 7)
        let edited = makeEntry(subject: .movie(2), score: 6)
        try await store.apply(.replaceDiary([other, edited]))
        try backdateDiary()

        var rerated = edited
        rerated.score = 9
        try await store.apply(.replaceDiary([other, rerated]))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarText("SELECT updated_at FROM diary_entry WHERE tmdb_id = 1;"), Self.oldDate)
        XCTAssertEqual(try db.scalarInt("SELECT revision FROM diary_entry WHERE tmdb_id = 1;"), 1)
    }

    func test_replaceDiary_changedEntry_bumpsRevisionAndKeepsCreatedAt() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let entry = makeEntry(subject: .movie(2), score: 6)
        try await store.apply(.replaceDiary([entry]))
        try backdateDiary()

        var edited = entry
        edited.watchedOn = DiaryDay(year: 2026, month: 9, day: 1)
        try await store.apply(.replaceDiary([edited]))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT revision FROM diary_entry;"), 2)
        XCTAssertNotEqual(try db.scalarText("SELECT updated_at FROM diary_entry;"), Self.oldDate)
        XCTAssertEqual(try db.scalarText("SELECT created_at FROM diary_entry;"), Self.oldDate)
        XCTAssertEqual(try db.scalarText("SELECT watched_on FROM diary_entry;"), "2026-09-01")
    }

    func test_replaceDiary_unchangedEntries_keepRevision() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let entries = [makeEntry(subject: .movie(1)), makeEntry(subject: .movie(1), isRewatch: true)]

        try await store.apply(.replaceDiary(entries))
        try await store.apply(.replaceDiary(entries))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM diary_entry;"), 1)
    }

    func test_replaceDiary_removedEntry_leavesTombstoneAndHidesIt() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let kept = makeEntry(subject: .movie(1))
        let removed = makeEntry(subject: .movie(1), isRewatch: true)
        try await store.apply(.replaceDiary([kept, removed]))

        try await store.apply(.replaceDiary([kept]))

        let loaded = try await store.fetchDiaryEntries()
        XCTAssertEqual(loaded.map(\.id), [kept.id])
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM diary_entry;"), 2)
        XCTAssertEqual(
            try db.scalarInt(
                "SELECT revision FROM diary_entry WHERE id = '\(removed.id.uuidString)' AND deleted_at IS NOT NULL;"
            ),
            2
        )
    }

    func test_replaceDiary_reSavedTombstone_revivesRow() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let entry = makeEntry(subject: .movie(1))
        try await store.apply(.replaceDiary([entry]))
        try await store.apply(.replaceDiary([]))

        try await store.apply(.replaceDiary([entry]))

        let loaded = try await store.fetchDiaryEntries()
        XCTAssertEqual(loaded, [entry])
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM diary_entry;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT revision FROM diary_entry;"), 3)
    }

    func test_replaceDiary_doesNotTouchOtherDomains() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let list = LibraryList.system(.watched)
        try await store.apply(
            .replaceLists(
                LibrarySnapshot(
                    lists: [list],
                    entries: [ListEntry(listID: list.id, draft: draft(5), addedAt: Date(), position: 0)]
                )
            )
        )
        try await store.apply(
            .replaceAnnotations([MediaAnnotation(key: .movie(5), score: 8, note: nil, watchedAt: Date())])
        )

        try await store.apply(.replaceDiary([makeEntry(subject: .movie(5))]))
        try await store.apply(.replaceDiary([]))

        let snapshot = try await store.fetchSnapshot()
        XCTAssertEqual(snapshot.entries.map(\.itemID), [5])
        let annotations = try await store.fetchAnnotations()
        XCTAssertEqual(annotations.map(\.score), [8])
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM annotation;"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT MAX(revision) FROM list_membership;"), 1)
    }

    func test_replaceDiary_leavesUnusedTagsColumnAtItsDefault() async throws {
        let store = try makeStore()
        try await store.bootstrap()

        try await store.apply(.replaceDiary([makeEntry(subject: .movie(1)), makeEntry(subject: .series(2))]))

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM diary_entry WHERE tags_json = '[]';"), 2)
    }

    func test_replaceDiary_storesNormalizedEntry() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let entry = makeEntry(subject: .movie(1), score: 11, review: "   ")

        try await store.apply(.replaceDiary([entry]))

        let loaded = try await store.fetchDiaryEntries()
        XCTAssertNil(loaded.first?.score)
        XCTAssertNil(loaded.first?.review)
    }

    func test_fetchDiaryEntries_ordersNewestWatchFirst() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let older = makeEntry(subject: .movie(1), watchedOn: DiaryDay(year: 2025, month: 12, day: 31))
        let newer = makeEntry(subject: .movie(2), watchedOn: DiaryDay(year: 2026, month: 1, day: 1))

        try await store.apply(.replaceDiary([older, newer]))

        let loaded = try await store.fetchDiaryEntries()
        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
    }

    func test_diaryAdapter_roundTripsThroughSharedStore() async throws {
        let store = try makeStore()
        let adapter = LibraryDiaryStoreAdapter(library: store)
        let entry = makeEntry(subject: .movie(3))

        try await adapter.save([entry])

        let loaded = try await adapter.load()
        XCTAssertEqual(loaded, [entry])
    }

    // MARK: - Helpers

    /// A v3 database: Watched holds two movies and a series (plus one tombstoned movie),
    /// Watchlist holds a fourth movie. Annotations rate 550 and the series and one episode.
    private func writeV3Fixture() throws {
        let fixture = try SQLiteDatabase(fileURL: databaseURL())
        defer { fixture.close() }
        try fixture.execute("BEGIN IMMEDIATE;")
        for statement in LibrarySchema.v1Statements + LibrarySchema.v2Statements + LibrarySchema.v3Statements {
            try fixture.execute(statement)
        }
        try fixture.execute(
            """
            INSERT INTO schema_migrations (version, applied_at) VALUES
              (1, '2020-01-01T00:00:00.000Z'), (2, '2020-01-01T00:00:00.000Z'), (3, '2020-01-01T00:00:00.000Z');
            INSERT INTO library_list
              (id, name, segment, system_kind, sort, position, created_at, updated_at, revision, deleted_at)
            VALUES
              ('L1', 'Watched', 'moviesAndTV', 'watched', 'dateAdded', 0,
               '2023-01-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL),
              ('L2', 'Watchlist', 'moviesAndTV', 'watchlist', 'dateAdded', 1,
               '2023-01-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL);
            INSERT INTO media_item
              (item_key, tmdb_id, kind, title, image_path, release_date, genre_names_json,
               vote_average, popularity, updated_at, revision, deleted_at)
            VALUES
              ('movie-550', 550, 'movie', 'Fight Club', '/fc.jpg', '1999-10-15T00:00:00.000Z', '[]',
               8.4, 40, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('movie-600', 600, 'movie', 'Other', NULL, NULL, '[]', 7, 10, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('tv-42', 42, 'tv', 'Show', NULL, NULL, '[]', 8, 10, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('movie-700', 700, 'movie', 'Later', NULL, NULL, '[]', 6, 10, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('movie-800', 800, 'movie', 'Removed', NULL, NULL, '[]', 6, 10, '2026-10-01T00:00:00.000Z', 1, NULL);
            INSERT INTO list_membership
              (id, list_id, item_key, added_at, position, updated_at, revision, deleted_at)
            VALUES
              ('M1', 'L1', 'movie-550', '2024-03-01T12:00:00.000Z', 0, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('M2', 'L1', 'movie-600', '2025-05-01T12:00:00.000Z', 1, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('M3', 'L1', 'tv-42', '2025-02-01T12:00:00.000Z', 2, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('M4', 'L2', 'movie-700', '2025-02-01T12:00:00.000Z', 0, '2026-10-01T00:00:00.000Z', 1, NULL),
              ('M5', 'L1', 'movie-800', '2025-02-01T12:00:00.000Z', 3, '2026-10-01T00:00:00.000Z', 2,
               '2026-10-01T00:00:00.000Z');
            INSERT INTO annotation
              (id, item_key, kind, subject_id, season_number, episode_number,
               score, note, watched_at, created_at, updated_at, revision, deleted_at)
            VALUES
              ('A1', 'movie-550-0-0', 'movie', 550, 0, 0, 8, 'Rules.',
               '2023-07-04T12:00:00.000Z', '2023-07-04T12:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL),
              ('A2', 'tvSeries-42-0-0', 'tvSeries', 42, 0, 0, 9, NULL,
               '2025-06-01T12:00:00.000Z', '2025-06-01T12:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL),
              ('A3', 'tvEpisode-42-1-1', 'tvEpisode', 42, 1, 1, 4, NULL,
               '2025-01-15T12:00:00.000Z', '2025-01-15T12:00:00.000Z', '2026-10-01T00:00:00.000Z', 1, NULL);
            INSERT INTO tv_series_watch
              (series_id, next_up_season, next_up_episode, updated_at, revision, deleted_at)
            VALUES (42, 1, 2, '2026-09-01T00:00:00.000Z', 1, NULL);
            INSERT INTO tv_episode_completed
              (series_id, season_number, episode_number, completed_at, updated_at, revision, deleted_at)
            VALUES (42, 1, 1, '2025-01-15T12:00:00.000Z', '2025-01-15T12:00:00.000Z', 1, NULL);
            """
        )
        try fixture.execute("COMMIT;")
    }

    /// Moves every diary row's dates into the past, so a later write that touched a row
    /// is visible even within the same millisecond.
    private func backdateDiary() throws {
        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        try db.execute("UPDATE diary_entry SET updated_at = '\(Self.oldDate)', created_at = '\(Self.oldDate)';")
    }

    private func makeEntry(
        subject: DiarySubject,
        watchedOn: DiaryDay = DiaryDay(year: 2026, month: 10, day: 16),
        score: Double? = nil,
        review: String? = nil,
        isRewatch: Bool = false
    ) -> DiaryEntry {
        DiaryEntry(
            id: UUID(),
            subject: subject,
            title: "Title \(subject.tmdbID)",
            releaseYear: 2001,
            posterPath: "/p\(subject.tmdbID).jpg",
            watchedOn: watchedOn,
            score: score,
            review: review,
            isRewatch: isRewatch,
            loggedAt: date("2026-10-16T20:15:00.000Z")
        )
    }

    private func draft(_ id: Int) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .movie,
            title: "Movie \(id)",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 7,
            popularity: 10
        )
    }

    private func date(_ iso: String) -> Date {
        LibrarySQLDate.decode(iso)!
    }

    // MARK: - Episode entries (v5)

    func test_bootstrap_v5AddsEpisodeColumnsToDiary() async throws {
        let store = try makeStore()
        try await store.bootstrap()

        let db = try SQLiteDatabase(fileURL: databaseURL())
        defer { db.close() }
        XCTAssertEqual(
            try db.scalarInt(
                "SELECT COUNT(*) FROM pragma_table_info('diary_entry') WHERE name IN ('season_number', 'episode_number');"
            ),
            2
        )
    }

    func test_replaceDiary_roundTripsEpisodeAndKeepsSeriesEntriesWhole() async throws {
        let store = try makeStore()
        try await store.bootstrap()
        let episode = makeEntry(subject: .episode(seriesID: 42, season: 2, episode: 3), score: 8)
        let series = makeEntry(subject: .series(42))

        try await store.apply(.replaceDiary([episode, series]))

        let loaded = try await store.fetchDiaryEntries()
        XCTAssertEqual(loaded.first { $0.id == episode.id }?.subject, .episode(seriesID: 42, season: 2, episode: 3))
        XCTAssertEqual(loaded.first { $0.id == series.id }?.subject, .series(42))
        XCTAssertNil(loaded.first { $0.id == series.id }?.subject.episode)
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
