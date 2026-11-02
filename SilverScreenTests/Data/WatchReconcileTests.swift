//
//  WatchReconcileTests.swift
//  SilverScreenTests
//
//  Schema v6's data pass on a real library.sqlite built at v5. The rule under test: a
//  title is watched exactly when it has a watch, and nothing a person saved is lost.
//

import XCTest
@testable import SilverScreen

final class WatchReconcileTests: XCTestCase {
    private static let stamp = "2026-01-01T12:00:00.000Z"
    /// Real UUIDs: `fetchSnapshot` drops a list whose id does not parse.
    private static let watchedID = "11111111-1111-4111-8111-111111111111"
    private static let watchlistID = "22222222-2222-4222-8222-222222222222"
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchReconcileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func test_movieOnWatchedWithoutWatch_getsUndatedWatch() async throws {
        try writeV5 { db in
            try self.insertMovie(db, id: 1)
            try self.insertMembership(db, list: Self.watchedID, movie: 1)
        }

        let entries = try await migrate().fetchDiaryEntries()

        XCTAssertEqual(entries.map(\.subject), [.movie(1)])
        XCTAssertEqual(entries.first?.isDateKnown, false)
    }

    func test_movieWithWatchNotOnWatched_goesOnWatchedAndOffWatchlist() async throws {
        try writeV5 { db in
            try self.insertMovie(db, id: 1)
            try self.insertMembership(db, list: Self.watchlistID, movie: 1)
            try self.insertEntry(db, id: "e1", kind: "movie", tmdbID: 1)
        }

        let snapshot = try await migrate().fetchSnapshot()

        XCTAssertEqual(snapshot.entries.map(\.itemKey), ["movie-1"])
        XCTAssertEqual(snapshot.entries.first?.listID, snapshot.list(.watched)?.id)
    }

    func test_scoredMovieWithNoWatch_getsWatchAndGoesOnWatched() async throws {
        try writeV5 { db in
            try self.insertMovie(db, id: 1)
            try self.insertAnnotation(db, kind: "movie", subject: 1, score: 8, note: nil)
        }

        let store = try migrate()
        let entries = try await store.fetchDiaryEntries()
        let snapshot = try await store.fetchSnapshot()

        XCTAssertEqual(entries.first?.score, 8)
        XCTAssertEqual(entries.first?.isDateKnown, false)
        XCTAssertEqual(snapshot.entries.map(\.itemKey), ["movie-1"])
    }

    func test_noteOnlyMovie_staysOnAnnotationWithNoWatch() async throws {
        try writeV5 { db in
            try self.insertMovie(db, id: 1)
            try self.insertAnnotation(db, kind: "movie", subject: 1, score: nil, note: "Want to see")
        }

        let store = try migrate()
        let entries = try await store.fetchDiaryEntries()
        let annotations = try await store.fetchAnnotations()

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(annotations.first?.note, "Want to see")
    }

    func test_savedScoreAndNote_moveOntoNewestWatch() async throws {
        try writeV5 { db in
            try self.insertMovie(db, id: 1)
            try self.insertMembership(db, list: Self.watchedID, movie: 1)
            try self.insertEntry(db, id: "old", kind: "movie", tmdbID: 1, day: "2025-01-01", score: 5)
            try self.insertEntry(db, id: "new", kind: "movie", tmdbID: 1, day: "2026-01-01", review: "Great")
            try self.insertAnnotation(db, kind: "movie", subject: 1, score: 9, note: "Rewatch soon")
        }

        let store = try migrate()
        let entries = try await store.fetchDiaryEntries()
        let annotations = try await store.fetchAnnotations()

        let newest = entries.first { $0.watchedOn.year == 2026 }
        XCTAssertEqual(newest?.score, 9)
        XCTAssertEqual(newest?.review, "Great\n\nRewatch soon")
        XCTAssertEqual(entries.first { $0.watchedOn.year == 2025 }?.score, 5)
        XCTAssertEqual(annotations.first?.score, 9)
        XCTAssertNil(annotations.first?.note)
    }

    func test_mergedReview_dropsNoteAlreadyInReview() {
        XCTAssertEqual(SQLiteLibraryStore.mergedReview("Loved it", note: "Loved it"), "Loved it")
        XCTAssertEqual(SQLiteLibraryStore.mergedReview(nil, note: " Loved it "), "Loved it")
    }

    func test_completedEpisode_becomesWatchDatedItsCheckOff_andKeepsProgress() async throws {
        try writeV5 { db in
            try self.insertShowProgress(db, seriesID: 42, season: 1, episode: 2)
        }

        let store = try migrate()
        let entries = try await store.fetchDiaryEntries()
        let states = try await store.fetchTVWatchStates()

        XCTAssertEqual(entries.map(\.subject), [.episode(seriesID: 42, season: 1, episode: 2)])
        XCTAssertEqual(entries.first?.watchedOn, DiaryDay(year: 2026, month: 1, day: 1))
        XCTAssertEqual(entries.first?.isDateKnown, true)
        XCTAssertEqual(states.first?.completedCount, 1)
    }

    func test_episodeScore_withoutCheckOff_createsNoWatch() async throws {
        try writeV5 { db in
            try self.insertAnnotation(db, kind: "tvEpisode", subject: 42, season: 1, episode: 1, score: 7, note: nil)
        }

        let store = try migrate()
        let entries = try await store.fetchDiaryEntries()
        let annotations = try await store.fetchAnnotations()

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(annotations.first?.score, 7)
    }

    func test_seriesEntry_withEpisodes_becomesVerdict() async throws {
        try writeV5 { db in
            try self.insertShowProgress(db, seriesID: 42, season: 1, episode: 1)
            try self.insertEntry(db, id: "s", kind: "tv", tmdbID: 42, score: 7, review: "Good show")
        }

        let store = try migrate()
        let entries = try await store.fetchDiaryEntries()
        let annotations = try await store.fetchAnnotations()

        XCTAssertFalse(entries.contains { $0.subject == .series(42) })
        XCTAssertEqual(annotations.first { $0.key == .series(42) }?.score, 7)
        XCTAssertEqual(annotations.first { $0.key == .series(42) }?.note, "Good show")
    }

    func test_seriesEntry_existingVerdictWins() async throws {
        try writeV5 { db in
            try self.insertShowProgress(db, seriesID: 42, season: 1, episode: 1)
            try self.insertEntry(db, id: "s", kind: "tv", tmdbID: 42, score: 7)
            try self.insertAnnotation(db, kind: "tvSeries", subject: 42, score: 9, note: nil)
        }

        let annotations = try await migrate().fetchAnnotations()

        XCTAssertEqual(annotations.first { $0.key == .series(42) }?.score, 9)
    }

    func test_seriesEntry_clearedVerdict_takesEntryValuesNotTheClearedOnes() async throws {
        try writeV5 { db in
            try self.insertShowProgress(db, seriesID: 42, season: 1, episode: 1)
            try self.insertEntry(db, id: "s", kind: "tv", tmdbID: 42, score: 7)
            try self.insertAnnotation(db, kind: "tvSeries", subject: 42, score: 3, note: "Old take")
            try db.execute("UPDATE annotation SET deleted_at = '\(Self.stamp)' WHERE kind = 'tvSeries';")
        }

        let annotations = try await migrate().fetchAnnotations()

        let verdict = annotations.first { $0.key == .series(42) }
        XCTAssertEqual(verdict?.score, 7)
        XCTAssertNil(verdict?.note)
    }

    func test_seriesEntry_withNoEpisodes_stays() async throws {
        try writeV5 { db in
            try self.insertEntry(db, id: "s", kind: "tv", tmdbID: 42)
        }

        let entries = try await migrate().fetchDiaryEntries()

        XCTAssertEqual(entries.map(\.subject), [.series(42)])
    }

    func test_reconcileTwice_addsNothing() async throws {
        try writeV5 { db in
            try self.insertMovie(db, id: 1)
            try self.insertMembership(db, list: Self.watchedID, movie: 1)
            try self.insertShowProgress(db, seriesID: 42, season: 1, episode: 1)
            try self.insertAnnotation(db, kind: "movie", subject: 1, score: 8, note: "Good")
        }
        let store = try migrate()
        let first = try await store.fetchDiaryEntries()

        try await store.reconcileWatchesNow()

        let second = try await store.fetchDiaryEntries()
        XCTAssertEqual(first, second)
    }

    // MARK: - Helpers

    private func migrate() throws -> SQLiteLibraryStore {
        try SQLiteLibraryStore(
            databaseURL: directory.appendingPathComponent("library.sqlite"),
            listsJSONURL: directory.appendingPathComponent("lists.json"),
            annotationsJSONURL: directory.appendingPathComponent("annotations.json"),
            tvWatchJSONURL: directory.appendingPathComponent("tv-progress.json")
        )
    }

    /// Builds a v5 database with empty Watched and Watchlist, then runs `seed`.
    private func writeV5(_ seed: @escaping (SQLiteDatabase) throws -> Void) throws {
        let db = try SQLiteDatabase(fileURL: directory.appendingPathComponent("library.sqlite"))
        defer { db.close() }
        try db.execute("BEGIN IMMEDIATE;")
        for version in 1...5 {
            for statement in try LibrarySchema.statements(for: version) {
                try db.execute(statement)
            }
            try db.execute("INSERT INTO schema_migrations (version, applied_at) VALUES (\(version), '\(Self.stamp)');")
        }
        try db.execute(
            """
            INSERT INTO library_list
              (id, name, segment, system_kind, sort, position, created_at, updated_at)
            VALUES
              ('\(Self.watchedID)', 'Watched', 'moviesAndTV', 'watched', 'dateAdded', 0, '\(Self.stamp)', '\(Self.stamp)'),
              ('\(Self.watchlistID)', 'Watchlist', 'moviesAndTV', 'watchlist', 'dateAdded', 1, '\(Self.stamp)', '\(Self.stamp)');
            """
        )
        try seed(db)
        try db.execute("COMMIT;")
    }

    private static func sql(_ value: Double?) -> String {
        value.map { "\($0)" } ?? "NULL"
    }

    private static func sql(_ value: String?) -> String {
        value.map { "'\($0)'" } ?? "NULL"
    }

    private func insertMovie(_ db: SQLiteDatabase, id: Int) throws {
        try db.execute(
            """
            INSERT INTO media_item (item_key, tmdb_id, kind, title, updated_at)
            VALUES ('movie-\(id)', \(id), 'movie', 'Movie \(id)', '\(Self.stamp)');
            """
        )
    }

    private func insertMembership(_ db: SQLiteDatabase, list: String, movie: Int) throws {
        try db.execute(
            """
            INSERT INTO list_membership (id, list_id, item_key, added_at, position, updated_at)
            VALUES ('\(list)-\(movie)', '\(list)', 'movie-\(movie)', '\(Self.stamp)', 0, '\(Self.stamp)');
            """
        )
    }

    private func insertEntry(
        _ db: SQLiteDatabase,
        id: String,
        kind: String,
        tmdbID: Int,
        day: String = "2026-01-01",
        score: Double? = nil,
        review: String? = nil
    ) throws {
        try db.execute(
            """
            INSERT INTO diary_entry
              (id, kind, tmdb_id, title, watched_on, score, review, logged_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)', '\(kind)', \(tmdbID), 'Title \(id)', '\(day)',
                    \(Self.sql(score)), \(Self.sql(review)),
                    '\(day)T12:00:00.000Z', '\(Self.stamp)', '\(Self.stamp)');
            """
        )
    }

    private func insertAnnotation(
        _ db: SQLiteDatabase,
        kind: String,
        subject: Int,
        season: Int = 0,
        episode: Int = 0,
        score: Double?,
        note: String?
    ) throws {
        try db.execute(
            """
            INSERT INTO annotation
              (id, item_key, kind, subject_id, season_number, episode_number,
               score, note, watched_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)', '\(kind)-\(subject)', '\(kind)', \(subject), \(season), \(episode),
                    \(Self.sql(score)), \(Self.sql(note)),
                    '\(Self.stamp)', '\(Self.stamp)', '\(Self.stamp)');
            """
        )
    }

    private func insertShowProgress(_ db: SQLiteDatabase, seriesID: Int, season: Int, episode: Int) throws {
        try db.execute(
            """
            INSERT INTO media_item (item_key, tmdb_id, kind, title, updated_at)
            VALUES ('tv-\(seriesID)', \(seriesID), 'tv', 'Show', '\(Self.stamp)');
            INSERT INTO tv_series_watch (series_id, updated_at) VALUES (\(seriesID), '\(Self.stamp)');
            INSERT INTO tv_episode_completed
              (series_id, season_number, episode_number, completed_at, updated_at)
            VALUES (\(seriesID), \(season), \(episode), '\(Self.stamp)', '\(Self.stamp)');
            """
        )
    }
}
