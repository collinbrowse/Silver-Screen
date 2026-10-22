//
//  LibrarySchema.swift
//  SilverScreen
//
//  Explicit SQL migrations for library.sqlite. Version N→N+1 is additive and tested.
//  SQLiteLibraryStore applies these statements; this type never holds a connection.
//

import Foundation

enum LibrarySchema {
    static let currentVersion = 4

    static let v1Statements: [String] = [
        """
        CREATE TABLE schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE media_item (
          item_key TEXT PRIMARY KEY,
          tmdb_id INTEGER NOT NULL,
          kind TEXT NOT NULL,
          title TEXT NOT NULL,
          image_path TEXT,
          release_date TEXT,
          genre_names_json TEXT NOT NULL DEFAULT '[]',
          vote_average REAL NOT NULL DEFAULT 0,
          popularity REAL NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 1,
          deleted_at TEXT
        );
        """,
        """
        CREATE TABLE library_list (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          segment TEXT NOT NULL,
          system_kind TEXT,
          sort TEXT NOT NULL,
          position INTEGER NOT NULL,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 1,
          deleted_at TEXT
        );
        """,
        """
        CREATE TABLE list_membership (
          id TEXT PRIMARY KEY,
          list_id TEXT NOT NULL REFERENCES library_list(id),
          item_key TEXT NOT NULL REFERENCES media_item(item_key),
          added_at TEXT NOT NULL,
          position INTEGER NOT NULL,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 1,
          deleted_at TEXT,
          UNIQUE(list_id, item_key)
        );
        """,
        """
        CREATE INDEX list_membership_list_position
          ON list_membership(list_id, position);
        """,
        """
        CREATE INDEX list_membership_item_key
          ON list_membership(item_key);
        """,
        """
        CREATE TABLE annotation (
          id TEXT PRIMARY KEY,
          item_key TEXT NOT NULL,
          kind TEXT NOT NULL,
          subject_id INTEGER NOT NULL,
          season_number INTEGER NOT NULL DEFAULT 0,
          episode_number INTEGER NOT NULL DEFAULT 0,
          score REAL,
          note TEXT,
          watched_at TEXT,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 1,
          deleted_at TEXT,
          UNIQUE(kind, subject_id, season_number, episode_number)
        );
        """,
        """
        CREATE TABLE tv_series_watch (
          series_id INTEGER PRIMARY KEY,
          next_up_season INTEGER,
          next_up_episode INTEGER,
          next_up_title TEXT,
          catalog_snapshot_json TEXT,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 1,
          deleted_at TEXT
        );
        """,
        """
        CREATE TABLE tv_episode_completed (
          series_id INTEGER NOT NULL REFERENCES tv_series_watch(series_id) ON DELETE CASCADE,
          season_number INTEGER NOT NULL,
          episode_number INTEGER NOT NULL,
          PRIMARY KEY (series_id, season_number, episode_number)
        );
        """,
        """
        CREATE TABLE sync_outbox (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          op TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT
        );
        """,
        """
        CREATE INDEX sync_outbox_entity ON sync_outbox(entity_type, entity_id);
        """,
        """
        CREATE TABLE sync_state (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """,
    ]

    /// Sort helper for later SQL-backed shelves; ships as v2 so N→N+1 is tested.
    static let v2Statements: [String] = [
        """
        CREATE INDEX media_item_kind_popularity
          ON media_item(kind, popularity);
        """,
    ]

    /// History-safe writes: creation dates on lists, annotations, and completed episodes,
    /// plus sync metadata so unmarking an episode leaves a tombstone. Each date is
    /// backfilled from the best one already stored, falling back to the row's last
    /// `updated_at` (never later than the migration).
    static let v3Statements: [String] = [
        "ALTER TABLE library_list ADD COLUMN created_at TEXT;",
        """
        UPDATE library_list SET created_at = COALESCE(
          (SELECT MIN(m.added_at) FROM list_membership m WHERE m.list_id = library_list.id),
          updated_at,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        );
        """,
        "ALTER TABLE annotation ADD COLUMN created_at TEXT;",
        """
        UPDATE annotation SET created_at = COALESCE(
          watched_at,
          (SELECT MIN(m.added_at) FROM list_membership m
            WHERE m.item_key = CASE annotation.kind
              WHEN 'movie' THEN 'movie-' || annotation.subject_id
              WHEN 'tvSeries' THEN 'tv-' || annotation.subject_id
            END),
          updated_at,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        );
        """,
        "ALTER TABLE tv_episode_completed ADD COLUMN completed_at TEXT;",
        "ALTER TABLE tv_episode_completed ADD COLUMN updated_at TEXT;",
        "ALTER TABLE tv_episode_completed ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;",
        "ALTER TABLE tv_episode_completed ADD COLUMN deleted_at TEXT;",
        """
        UPDATE tv_episode_completed SET completed_at = COALESCE(
          (SELECT a.watched_at FROM annotation a
            WHERE a.kind = 'tvEpisode'
              AND a.subject_id = tv_episode_completed.series_id
              AND a.season_number = tv_episode_completed.season_number
              AND a.episode_number = tv_episode_completed.episode_number),
          (SELECT w.updated_at FROM tv_series_watch w
            WHERE w.series_id = tv_episode_completed.series_id),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        );
        """,
        "UPDATE tv_episode_completed SET updated_at = completed_at;",
    ]

    /// Diary: one row per logged watch, many per title, with the same sync metadata as
    /// every other table. `watched_on` is a `yyyy-MM-dd` calendar day. The backfill (one
    /// entry per title on Watched) runs in Swift inside the same migration transaction,
    /// because its ids come from `LibraryStableID`; see `SQLiteLibraryStore+Diary.swift`.
    static let v4Statements: [String] = [
        """
        CREATE TABLE diary_entry (
          id TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          tmdb_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          release_year INTEGER,
          image_path TEXT,
          watched_on TEXT NOT NULL,
          score REAL,
          review TEXT,
          is_rewatch INTEGER NOT NULL DEFAULT 0,
          tags_json TEXT NOT NULL DEFAULT '[]',
          logged_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 1,
          deleted_at TEXT
        );
        """,
        "CREATE INDEX diary_entry_watched_on ON diary_entry(watched_on);",
        "CREATE INDEX diary_entry_subject ON diary_entry(kind, tmdb_id);",
    ]

    /// SQL for a single schema version. Unknown versions fail instead of no-op.
    static func statements(for version: Int) throws -> [String] {
        switch version {
            case 1: return v1Statements
            case 2: return v2Statements
            case 3: return v3Statements
            case 4: return v4Statements
            default:
                throw SQLiteDatabaseError.executionFailed(
                    message: "unknown library schema version \(version)"
                )
        }
    }
}

/// ISO-8601 timestamps stored in TEXT columns, including fractional seconds.
enum LibrarySQLDate {
    static func encode(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func decode(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

/// Stable ids so a diffed write matches each snapshot row to the row it already stored.
enum LibraryStableID {
    /// Deterministic UUID so every save maps to the same membership/annotation ids.
    static func uuid(from string: String) -> UUID {
        var hash = [UInt8](repeating: 0, count: 16)
        let data = Data(string.utf8)
        // FNV-1a 128-bit style fold — stable across launches, no CryptoKit dependency surface.
        var h1: UInt64 = 0xcbf2_9ce4_8422_2325
        var h2: UInt64 = 0x1000_0000_01b3
        for byte in data {
            h1 ^= UInt64(byte)
            h1 = h1 &* 0x1000_0000_01b3
            h2 ^= UInt64(byte &* 31)
            h2 = h2 &* 0x1000_0000_01b3
        }
        withUnsafeBytes(of: h1.bigEndian) { hash.replaceSubrange(0..<8, with: $0) }
        withUnsafeBytes(of: h2.bigEndian) { hash.replaceSubrange(8..<16, with: $0) }
        hash[6] = (hash[6] & 0x0F) | 0x40
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }
}
