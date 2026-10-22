//
//  SQLiteLibraryStore+Diary.swift
//  SilverScreen
//
//  Diary reads, diffed writes, and the schema v4 backfill. Kept beside the store
//  rather than inside it so the diary domain reads on its own; it follows the same
//  rules as the other domains (one transaction per save, tombstones, revisions).
//

import Foundation

extension SQLiteLibraryStore {
    /// Every live diary entry, newest watch first, then newest log first.
    func fetchDiaryEntries() async throws -> [DiaryEntry] {
        try await ensureBootstrapped()
        var entries: [DiaryEntry] = []
        try database.collect(
            """
            SELECT id, kind, tmdb_id, title, release_year, image_path, watched_on,
                   score, review, is_rewatch, tags_json, logged_at
            FROM diary_entry
            WHERE deleted_at IS NULL
            ORDER BY watched_on DESC, logged_at DESC;
            """
        ) { statement in
            guard
                let idRaw = SQLiteBinding.columnText(statement, index: 0),
                let id = UUID(uuidString: idRaw),
                let kindRaw = SQLiteBinding.columnText(statement, index: 1),
                let kind = ListItemKind(rawValue: kindRaw),
                kind != .person,
                let title = SQLiteBinding.columnText(statement, index: 3),
                let watchedOnRaw = SQLiteBinding.columnText(statement, index: 6),
                let watchedOn = DiaryDay(iso: watchedOnRaw),
                let loggedAt = LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 11))
            else {
                return
            }
            let tagsJSON = SQLiteBinding.columnText(statement, index: 10) ?? "[]"
            entries.append(
                DiaryEntry(
                    id: id,
                    subject: DiarySubject(kind: kind, tmdbID: SQLiteBinding.columnInt(statement, index: 2)),
                    title: title,
                    releaseYear: SQLiteBinding.columnIsNull(statement, index: 4)
                        ? nil
                        : SQLiteBinding.columnInt(statement, index: 4),
                    posterPath: SQLiteBinding.columnText(statement, index: 5),
                    watchedOn: watchedOn,
                    score: SQLiteBinding.columnIsNull(statement, index: 7)
                        ? nil
                        : SQLiteBinding.columnDouble(statement, index: 7),
                    review: SQLiteBinding.columnText(statement, index: 8),
                    isRewatch: SQLiteBinding.columnInt(statement, index: 9) != 0,
                    tags: (try? decoder.decode([String].self, from: Data(tagsJSON.utf8))) ?? [],
                    loggedAt: loggedAt
                )
            )
        }
        return entries
    }

    func replaceDiary(_ entries: [DiaryEntry]) throws {
        try withTransaction { try writeDiary(entries) }
    }

    /// Diffs `entries` against the stored rows by id: new ids insert, changed rows bump
    /// `revision` and `updated_at`, identical rows are left alone, a tombstoned id is
    /// revived, and live rows missing from `entries` are tombstoned.
    private func writeDiary(_ entries: [DiaryEntry]) throws {
        let now = LibrarySQLDate.encode(Date())
        var ids = Set<String>()
        for raw in entries {
            let entry = raw.normalized()
            guard entry.subject.kind != .person else { continue }
            let id = entry.id.uuidString
            guard ids.insert(id).inserted else { continue }
            let tagsJSON = String(
                data: (try? encoder.encode(entry.tags)) ?? Data("[]".utf8),
                encoding: .utf8
            ) ?? "[]"
            try database.run(
                """
                INSERT INTO diary_entry
                  (id, kind, tmdb_id, title, release_year, image_path, watched_on,
                   score, review, is_rewatch, tags_json, logged_at,
                   created_at, updated_at, revision, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?13, ?13, 1, NULL)
                ON CONFLICT(id) DO UPDATE SET
                  kind = excluded.kind,
                  tmdb_id = excluded.tmdb_id,
                  title = excluded.title,
                  release_year = excluded.release_year,
                  image_path = excluded.image_path,
                  watched_on = excluded.watched_on,
                  score = excluded.score,
                  review = excluded.review,
                  is_rewatch = excluded.is_rewatch,
                  tags_json = excluded.tags_json,
                  logged_at = excluded.logged_at,
                  created_at = CASE WHEN diary_entry.deleted_at IS NULL
                    THEN diary_entry.created_at ELSE excluded.created_at END,
                  updated_at = excluded.updated_at,
                  revision = diary_entry.revision + 1,
                  deleted_at = NULL
                WHERE diary_entry.deleted_at IS NOT NULL
                   OR diary_entry.kind IS NOT excluded.kind
                   OR diary_entry.tmdb_id IS NOT excluded.tmdb_id
                   OR diary_entry.title IS NOT excluded.title
                   OR diary_entry.release_year IS NOT excluded.release_year
                   OR diary_entry.image_path IS NOT excluded.image_path
                   OR diary_entry.watched_on IS NOT excluded.watched_on
                   OR diary_entry.score IS NOT excluded.score
                   OR diary_entry.review IS NOT excluded.review
                   OR diary_entry.is_rewatch IS NOT excluded.is_rewatch
                   OR diary_entry.tags_json IS NOT excluded.tags_json
                   OR diary_entry.logged_at IS NOT excluded.logged_at;
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, id)
                SQLiteBinding.text(statement, index: 2, entry.subject.kind.rawValue)
                SQLiteBinding.int(statement, index: 3, entry.subject.tmdbID)
                SQLiteBinding.text(statement, index: 4, entry.title)
                SQLiteBinding.int(statement, index: 5, entry.releaseYear)
                SQLiteBinding.text(statement, index: 6, entry.posterPath)
                SQLiteBinding.text(statement, index: 7, entry.watchedOn.iso)
                SQLiteBinding.double(statement, index: 8, entry.score)
                SQLiteBinding.text(statement, index: 9, entry.review)
                SQLiteBinding.int(statement, index: 10, entry.isRewatch ? 1 : 0)
                SQLiteBinding.text(statement, index: 11, tagsJSON)
                SQLiteBinding.text(statement, index: 12, LibrarySQLDate.encode(entry.loggedAt))
                SQLiteBinding.text(statement, index: 13, now)
            }
        }
        try tombstoneRows(in: "diary_entry", keyExpression: "id", keeping: ids, now: now)
    }

    /// Gives every live movie or series on Watched one diary entry, so history from before
    /// the diary is not lost. The watch day is the earliest evidence stored: the title's
    /// first rating or note (`annotation.watched_at`) or the day it joined Watched,
    /// whichever came first, on the device's calendar. The title's current rating and
    /// note become the entry's rating and review.
    ///
    /// Ids are deterministic per title, so running this again (the legacy JSON import
    /// also calls it) never duplicates an entry or revives one the person deleted.
    /// Runs inside the caller's transaction.
    func backfillDiaryFromWatched(calendar: Calendar = .current) throws {
        struct Candidate {
            let kind: ListItemKind
            let tmdbID: Int
            let title: String
            let imagePath: String?
            let releaseDate: Date?
            let addedAt: Date?
            let ratedAt: Date?
            let score: Double?
            let note: String?
        }

        var candidates: [Candidate] = []
        try database.collect(
            """
            SELECT mi.kind, mi.tmdb_id, mi.title, mi.image_path, mi.release_date,
                   m.added_at, a.watched_at, a.score, a.note
            FROM list_membership m
            JOIN library_list l
              ON l.id = m.list_id AND l.system_kind = 'watched' AND l.deleted_at IS NULL
            JOIN media_item mi
              ON mi.item_key = m.item_key AND mi.deleted_at IS NULL
            LEFT JOIN annotation a
              ON a.deleted_at IS NULL
             AND a.subject_id = mi.tmdb_id
             AND a.season_number = 0
             AND a.episode_number = 0
             AND a.kind = CASE mi.kind WHEN 'movie' THEN 'movie' WHEN 'tv' THEN 'tvSeries' END
            WHERE m.deleted_at IS NULL
              AND mi.kind IN ('movie', 'tv');
            """
        ) { statement in
            guard
                let kindRaw = SQLiteBinding.columnText(statement, index: 0),
                let kind = ListItemKind(rawValue: kindRaw),
                let title = SQLiteBinding.columnText(statement, index: 2)
            else {
                return
            }
            candidates.append(
                Candidate(
                    kind: kind,
                    tmdbID: SQLiteBinding.columnInt(statement, index: 1),
                    title: title,
                    imagePath: SQLiteBinding.columnText(statement, index: 3),
                    releaseDate: LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 4)),
                    addedAt: LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 5)),
                    ratedAt: LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 6)),
                    score: SQLiteBinding.columnIsNull(statement, index: 7)
                        ? nil
                        : SQLiteBinding.columnDouble(statement, index: 7),
                    note: SQLiteBinding.columnText(statement, index: 8)
                )
            )
        }

        let migrationTime = Date()
        for candidate in candidates {
            let subject = DiarySubject(kind: candidate.kind, tmdbID: candidate.tmdbID)
            let watchedAt = [candidate.ratedAt, candidate.addedAt].compactMap { $0 }.min() ?? migrationTime
            let entry = DiaryEntry(
                id: Self.backfilledDiaryID(for: subject),
                subject: subject,
                title: candidate.title,
                releaseYear: candidate.releaseDate.map(Self.releaseYear),
                posterPath: candidate.imagePath,
                watchedOn: DiaryDay(watchedAt, calendar: calendar),
                score: candidate.score,
                review: candidate.note,
                isRewatch: false,
                tags: [],
                loggedAt: watchedAt
            ).normalized()
            let stamp = LibrarySQLDate.encode(watchedAt)
            try database.run(
                """
                INSERT INTO diary_entry
                  (id, kind, tmdb_id, title, release_year, image_path, watched_on,
                   score, review, is_rewatch, tags_json, logged_at,
                   created_at, updated_at, revision, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, '[]', ?10, ?10, ?10, 1, NULL)
                ON CONFLICT(id) DO NOTHING;
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, entry.id.uuidString)
                SQLiteBinding.text(statement, index: 2, entry.subject.kind.rawValue)
                SQLiteBinding.int(statement, index: 3, entry.subject.tmdbID)
                SQLiteBinding.text(statement, index: 4, entry.title)
                SQLiteBinding.int(statement, index: 5, entry.releaseYear)
                SQLiteBinding.text(statement, index: 6, entry.posterPath)
                SQLiteBinding.text(statement, index: 7, entry.watchedOn.iso)
                SQLiteBinding.double(statement, index: 8, entry.score)
                SQLiteBinding.text(statement, index: 9, entry.review)
                SQLiteBinding.text(statement, index: 10, stamp)
            }
        }
    }

    /// TMDB release dates are stored as UTC midnight, so the year is read in UTC.
    private static func releaseYear(_ date: Date) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.component(.year, from: date)
    }

    /// Runs the Watched backfill on its own, in one transaction. A demo launch seeds its
    /// library after migrating, so it calls this to get the diary an upgrade would have.
    func backfillDiaryFromWatchedNow() async throws {
        try await ensureBootstrapped()
        try withTransaction { try backfillDiaryFromWatched() }
    }

    /// The id a backfilled entry gets for `subject`. Two devices that backfill the same
    /// title agree on it, so a later sync merges them instead of doubling the entry.
    static func backfilledDiaryID(for subject: DiarySubject) -> UUID {
        LibraryStableID.uuid(from: "diary:backfill:\(subject.itemKey)")
    }
}
