//
//  SQLiteLibraryStore+WatchReconcile.swift
//  SilverScreen
//
//  Schema v6's data pass. Afterward a title is watched exactly when it has a diary
//  entry, and every saved rating and note sits on a watch or a verdict. Each pass is
//  idempotent, because the legacy JSON import runs them again after it writes its rows.
//

import Foundation

extension SQLiteLibraryStore {
    /// Runs inside the caller's transaction. Order matters: watches must exist before
    /// Watched is aligned to them, and before ratings and notes move onto them.
    func reconcileWatches(calendar: Calendar = .current) throws {
        try insertEpisodeWatches(calendar: calendar)
        try retireSeriesEntries()
        try insertMissingMovieWatches(calendar: calendar)
        try alignWatchedWithMovieWatches()
        try moveAnnotationsOntoWatches()
    }

    /// The note appended to a review, unless the review already says it (the v4 backfill
    /// copied notes into reviews).
    static func mergedReview(_ review: String?, note: String) -> String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let review, !review.isEmpty else { return trimmedNote }
        if trimmedNote.isEmpty || review.contains(trimmedNote) { return review }
        return "\(review)\n\n\(trimmedNote)"
    }

    /// Stable id of the diary entry for an episode's first watch.
    static func episodeWatchID(for subject: DiarySubject) -> UUID {
        let episode = subject.episode
        return LibraryStableID.uuid(
            from: "diary:episode:\(subject.tmdbID):\(episode?.seasonNumber ?? 0):\(episode?.episodeNumber ?? 0)"
        )
    }

    /// Stable id of a movie's reconciled watch. Separate from the v4 backfill's ids, so
    /// a backfilled entry the person deleted cannot block it.
    static func reconciledMovieWatchID(tmdbID: Int) -> UUID {
        LibraryStableID.uuid(from: "diary:reconcile:movie-\(tmdbID)")
    }

    // MARK: - Passes

    /// One entry per completed episode, dated its check-off. An episode whose series has
    /// no stored title is skipped: there is nothing to label the row with.
    private func insertEpisodeWatches(calendar: Calendar) throws {
        struct Row {
            let subject: DiarySubject
            let completedAt: Date
            let title: String
            let imagePath: String?
        }
        var rows: [Row] = []
        try database.collect(
            """
            SELECT c.series_id, c.season_number, c.episode_number, c.completed_at, m.title, m.image_path
            FROM tv_episode_completed c
            JOIN media_item m ON m.item_key = 'tv-' || c.series_id
            WHERE c.deleted_at IS NULL AND c.completed_at IS NOT NULL;
            """
        ) { statement in
            guard
                let completedAt = LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 3)),
                let title = SQLiteBinding.columnText(statement, index: 4)
            else {
                return
            }
            rows.append(
                Row(
                    subject: .episode(
                        seriesID: SQLiteBinding.columnInt(statement, index: 0),
                        season: SQLiteBinding.columnInt(statement, index: 1),
                        episode: SQLiteBinding.columnInt(statement, index: 2)
                    ),
                    completedAt: completedAt,
                    title: title,
                    imagePath: SQLiteBinding.columnText(statement, index: 5)
                )
            )
        }
        for row in rows {
            try insertWatch(
                id: Self.episodeWatchID(for: row.subject),
                subject: row.subject,
                title: row.title,
                imagePath: row.imagePath,
                watchedAt: row.completedAt,
                dateKnown: true,
                calendar: calendar
            )
        }
    }

    /// A show is watched through its episodes, so a whole-series entry goes once the show
    /// has any. Its rating and review become the show's verdict, filling only what is
    /// empty. A show with no check-offs keeps its entry, the only record of that watch.
    private func retireSeriesEntries() throws {
        struct Row {
            let id: String
            let seriesID: Int
            let score: Double?
            let review: String?
        }
        var rows: [Row] = []
        try database.collect(
            """
            SELECT d.id, d.tmdb_id, d.score, d.review
            FROM diary_entry d
            WHERE d.kind = 'tv' AND d.season_number IS NULL AND d.deleted_at IS NULL
              AND EXISTS (SELECT 1 FROM tv_episode_completed c
                          WHERE c.series_id = d.tmdb_id AND c.deleted_at IS NULL)
            ORDER BY d.watched_on DESC, d.logged_at DESC;
            """
        ) { statement in
            guard let id = SQLiteBinding.columnText(statement, index: 0) else { return }
            rows.append(
                Row(
                    id: id,
                    seriesID: SQLiteBinding.columnInt(statement, index: 1),
                    score: SQLiteBinding.columnIsNull(statement, index: 2)
                        ? nil
                        : SQLiteBinding.columnDouble(statement, index: 2),
                    review: SQLiteBinding.columnText(statement, index: 3)
                )
            )
        }
        let now = LibrarySQLDate.encode(Date())
        for row in rows {
            if row.score != nil || row.review != nil {
                try fillVerdict(seriesID: row.seriesID, score: row.score, note: row.review, now: now)
            }
            try database.run(
                "UPDATE diary_entry SET deleted_at = ?2, updated_at = ?2, revision = revision + 1 WHERE id = ?1;"
            ) { statement in
                SQLiteBinding.text(statement, index: 1, row.id)
                SQLiteBinding.text(statement, index: 2, now)
            }
        }
    }

    /// Gives an undated watch to each movie on Watched without one, and to each scored
    /// movie anywhere, since a rating says it was seen. A note alone does not count.
    private func insertMissingMovieWatches(calendar: Calendar) throws {
        struct Row {
            let tmdbID: Int
            let title: String
            let imagePath: String?
            let date: Date
        }
        var rows: [Row] = []
        try database.collect(
            """
            SELECT mi.tmdb_id, mi.title, mi.image_path,
                   COALESCE(
                     (SELECT m.added_at FROM list_membership m
                      JOIN library_list l ON l.id = m.list_id AND l.system_kind = 'watched'
                      WHERE m.item_key = mi.item_key AND m.deleted_at IS NULL AND l.deleted_at IS NULL),
                     a.watched_at,
                     mi.updated_at
                   )
            FROM media_item mi
            LEFT JOIN annotation a
              ON a.kind = 'movie' AND a.subject_id = mi.tmdb_id AND a.deleted_at IS NULL
            WHERE mi.kind = 'movie'
              AND NOT EXISTS (SELECT 1 FROM diary_entry d
                              WHERE d.kind = 'movie' AND d.tmdb_id = mi.tmdb_id AND d.deleted_at IS NULL)
              AND (a.score IS NOT NULL OR EXISTS (
                     SELECT 1 FROM list_membership m
                     JOIN library_list l ON l.id = m.list_id AND l.system_kind = 'watched'
                     WHERE m.item_key = mi.item_key AND m.deleted_at IS NULL AND l.deleted_at IS NULL));
            """
        ) { statement in
            guard
                let title = SQLiteBinding.columnText(statement, index: 1),
                let date = LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 3))
            else {
                return
            }
            rows.append(
                Row(
                    tmdbID: SQLiteBinding.columnInt(statement, index: 0),
                    title: title,
                    imagePath: SQLiteBinding.columnText(statement, index: 2),
                    date: date
                )
            )
        }
        for row in rows {
            try insertWatch(
                id: Self.reconciledMovieWatchID(tmdbID: row.tmdbID),
                subject: .movie(row.tmdbID),
                title: row.title,
                imagePath: row.imagePath,
                watchedAt: row.date,
                dateKnown: false,
                calendar: calendar
            )
        }
    }

    /// Puts each movie with a watch on Watched and off the Watchlist, matching what
    /// `addToWatched` does. Skipped until the system lists exist.
    private func alignWatchedWithMovieWatches() throws {
        var watchedID: String?
        try database.collect(
            "SELECT id FROM library_list WHERE system_kind = 'watched' AND deleted_at IS NULL LIMIT 1;"
        ) { statement in
            watchedID = SQLiteBinding.columnText(statement, index: 0)
        }
        guard let watchedID else { return }

        struct Row {
            let tmdbID: Int
            let title: String
            let imagePath: String?
            let firstLoggedAt: String
        }
        var rows: [Row] = []
        try database.collect(
            """
            SELECT d.tmdb_id, MAX(d.title), MAX(d.image_path), MIN(d.logged_at)
            FROM diary_entry d
            WHERE d.kind = 'movie' AND d.deleted_at IS NULL
              AND NOT EXISTS (SELECT 1 FROM list_membership m
                              WHERE m.list_id = ?1 AND m.deleted_at IS NULL
                                AND m.item_key = 'movie-' || d.tmdb_id)
            GROUP BY d.tmdb_id;
            """,
            binds: { statement in
                SQLiteBinding.text(statement, index: 1, watchedID)
            }
        ) { statement in
            guard
                let title = SQLiteBinding.columnText(statement, index: 1),
                let loggedAt = SQLiteBinding.columnText(statement, index: 3)
            else {
                return
            }
            rows.append(
                Row(
                    tmdbID: SQLiteBinding.columnInt(statement, index: 0),
                    title: title,
                    imagePath: SQLiteBinding.columnText(statement, index: 2),
                    firstLoggedAt: loggedAt
                )
            )
        }

        let now = LibrarySQLDate.encode(Date())
        for row in rows {
            let itemKey = "movie-\(row.tmdbID)"
            try database.run(
                """
                INSERT INTO media_item (item_key, tmdb_id, kind, title, image_path, updated_at)
                VALUES (?1, ?2, 'movie', ?3, ?4, ?5)
                ON CONFLICT(item_key) DO UPDATE SET
                  deleted_at = NULL,
                  updated_at = excluded.updated_at,
                  revision = media_item.revision + 1
                WHERE media_item.deleted_at IS NOT NULL;
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, itemKey)
                SQLiteBinding.int(statement, index: 2, row.tmdbID)
                SQLiteBinding.text(statement, index: 3, row.title)
                SQLiteBinding.text(statement, index: 4, row.imagePath)
                SQLiteBinding.text(statement, index: 5, now)
            }
            try database.run(
                """
                UPDATE list_membership
                SET deleted_at = NULL, added_at = ?3, updated_at = ?4, revision = revision + 1
                WHERE list_id = ?1 AND item_key = ?2;
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, watchedID)
                SQLiteBinding.text(statement, index: 2, itemKey)
                SQLiteBinding.text(statement, index: 3, row.firstLoggedAt)
                SQLiteBinding.text(statement, index: 4, now)
            }
            let membershipID = LibraryStableID.uuid(from: "membership:\(watchedID):\(itemKey)").uuidString
            try database.run(
                """
                INSERT OR IGNORE INTO list_membership
                  (id, list_id, item_key, added_at, position, updated_at, revision, deleted_at)
                VALUES (?1, ?2, ?3, ?4,
                        (SELECT COALESCE(MAX(position), -1) + 1 FROM list_membership WHERE list_id = ?2),
                        ?5, 1, NULL);
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, membershipID)
                SQLiteBinding.text(statement, index: 2, watchedID)
                SQLiteBinding.text(statement, index: 3, itemKey)
                SQLiteBinding.text(statement, index: 4, row.firstLoggedAt)
                SQLiteBinding.text(statement, index: 5, now)
            }
            try database.run(
                """
                UPDATE list_membership
                SET deleted_at = ?2, updated_at = ?2, revision = revision + 1
                WHERE item_key = ?1 AND deleted_at IS NULL
                  AND list_id IN (SELECT id FROM library_list WHERE system_kind = 'watchlist');
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, itemKey)
                SQLiteBinding.text(statement, index: 2, now)
            }
        }
    }

    /// Moves each movie's and episode's score and note onto its newest watch. The saved
    /// score wins over that watch's own, so every page shows the rating it showed before.
    /// The score stays on the annotation as the title's rating; a moved note leaves it.
    /// A title with no watch keeps its annotation: the Log sheet picks the note up later.
    private func moveAnnotationsOntoWatches() throws {
        struct Row {
            let id: String
            let kind: String
            let subjectID: Int
            let season: Int
            let episode: Int
            let score: Double?
            let note: String?
        }
        var rows: [Row] = []
        try database.collect(
            """
            SELECT id, kind, subject_id, season_number, episode_number, score, note
            FROM annotation
            WHERE deleted_at IS NULL AND kind IN ('movie', 'tvEpisode')
              AND (score IS NOT NULL OR note IS NOT NULL);
            """
        ) { statement in
            guard
                let id = SQLiteBinding.columnText(statement, index: 0),
                let kind = SQLiteBinding.columnText(statement, index: 1)
            else {
                return
            }
            rows.append(
                Row(
                    id: id,
                    kind: kind,
                    subjectID: SQLiteBinding.columnInt(statement, index: 2),
                    season: SQLiteBinding.columnInt(statement, index: 3),
                    episode: SQLiteBinding.columnInt(statement, index: 4),
                    score: SQLiteBinding.columnIsNull(statement, index: 5)
                        ? nil
                        : SQLiteBinding.columnDouble(statement, index: 5),
                    note: SQLiteBinding.columnText(statement, index: 6)
                )
            )
        }

        let now = LibrarySQLDate.encode(Date())
        for row in rows {
            let isEpisode = row.kind == "tvEpisode"
            var newestID: String?
            var review: String?
            try database.collect(
                """
                SELECT id, review FROM diary_entry
                WHERE deleted_at IS NULL AND kind = ?1 AND tmdb_id = ?2
                  AND season_number IS ?3 AND episode_number IS ?4
                ORDER BY date_known DESC, watched_on DESC, logged_at DESC
                LIMIT 1;
                """,
                binds: { statement in
                    SQLiteBinding.text(statement, index: 1, isEpisode ? "tv" : "movie")
                    SQLiteBinding.int(statement, index: 2, row.subjectID)
                    SQLiteBinding.int(statement, index: 3, isEpisode ? row.season : nil)
                    SQLiteBinding.int(statement, index: 4, isEpisode ? row.episode : nil)
                }
            ) { statement in
                newestID = SQLiteBinding.columnText(statement, index: 0)
                review = SQLiteBinding.columnText(statement, index: 1)
            }
            guard let newestID else { continue }

            let mergedReview = row.note.map { Self.mergedReview(review, note: $0) } ?? review
            try database.run(
                """
                UPDATE diary_entry
                SET score = COALESCE(?2, score), review = ?3, updated_at = ?4, revision = revision + 1
                WHERE id = ?1 AND (score IS NOT COALESCE(?2, score) OR review IS NOT ?3);
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, newestID)
                SQLiteBinding.double(statement, index: 2, row.score)
                SQLiteBinding.text(statement, index: 3, mergedReview)
                SQLiteBinding.text(statement, index: 4, now)
            }
            guard row.note != nil else { continue }
            try database.run(
                """
                UPDATE annotation
                SET note = NULL,
                    deleted_at = CASE WHEN score IS NULL THEN ?2 ELSE NULL END,
                    updated_at = ?2,
                    revision = revision + 1
                WHERE id = ?1;
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, row.id)
                SQLiteBinding.text(statement, index: 2, now)
            }
        }
    }

    // MARK: - Writes

    /// Inserts an unrated first watch. A row already stored under `id`, even a tombstone,
    /// is left alone, so running the pass again never revives a watch the person deleted.
    private func insertWatch(
        id: UUID,
        subject: DiarySubject,
        title: String,
        imagePath: String?,
        watchedAt: Date,
        dateKnown: Bool,
        calendar: Calendar
    ) throws {
        let stamp = LibrarySQLDate.encode(watchedAt)
        try database.run(
            """
            INSERT INTO diary_entry
              (id, kind, tmdb_id, title, image_path, watched_on, is_rewatch, logged_at,
               season_number, episode_number, date_known,
               created_at, updated_at, revision, deleted_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?8, ?9, ?10, ?7, ?7, 1, NULL)
            ON CONFLICT(id) DO NOTHING;
            """
        ) { statement in
            SQLiteBinding.text(statement, index: 1, id.uuidString)
            SQLiteBinding.text(statement, index: 2, subject.kind.rawValue)
            SQLiteBinding.int(statement, index: 3, subject.tmdbID)
            SQLiteBinding.text(statement, index: 4, title)
            SQLiteBinding.text(statement, index: 5, imagePath)
            SQLiteBinding.text(statement, index: 6, DiaryDay(watchedAt, calendar: calendar).iso)
            SQLiteBinding.text(statement, index: 7, stamp)
            SQLiteBinding.int(statement, index: 8, subject.episode?.seasonNumber)
            SQLiteBinding.int(statement, index: 9, subject.episode?.episodeNumber)
            SQLiteBinding.int(statement, index: 10, dateKnown ? 1 : 0)
        }
    }

    /// Fills the empty parts of a show's verdict, creating the row when there is none.
    private func fillVerdict(seriesID: Int, score: Double?, note: String?, now: String) throws {
        let id = LibraryStableID.uuid(from: "annotation:tvSeries:\(seriesID):0:0").uuidString
        try database.run(
            """
            INSERT INTO annotation
              (id, item_key, kind, subject_id, season_number, episode_number,
               score, note, watched_at, created_at, updated_at, revision, deleted_at)
            VALUES (?1, ?2, 'tvSeries', ?3, 0, 0, ?4, ?5, ?6, ?6, ?6, 1, NULL)
            ON CONFLICT(kind, subject_id, season_number, episode_number) DO UPDATE SET
              score = CASE WHEN annotation.deleted_at IS NOT NULL THEN excluded.score
                           ELSE COALESCE(annotation.score, excluded.score) END,
              note = CASE WHEN annotation.deleted_at IS NOT NULL THEN excluded.note
                          ELSE COALESCE(annotation.note, excluded.note) END,
              updated_at = excluded.updated_at,
              revision = annotation.revision + 1,
              deleted_at = NULL
            WHERE annotation.deleted_at IS NOT NULL
               OR (annotation.score IS NULL AND excluded.score IS NOT NULL)
               OR (annotation.note IS NULL AND excluded.note IS NOT NULL);
            """
        ) { statement in
            SQLiteBinding.text(statement, index: 1, id)
            SQLiteBinding.text(statement, index: 2, "tvSeries-\(seriesID)-0-0")
            SQLiteBinding.int(statement, index: 3, seriesID)
            SQLiteBinding.double(statement, index: 4, score)
            SQLiteBinding.text(statement, index: 5, note)
            SQLiteBinding.text(statement, index: 6, now)
        }
    }
}

extension SQLiteLibraryStore {
    /// Runs the pass again in its own transaction; tests use this to pin idempotence.
    func reconcileWatchesNow() async throws {
        try await ensureBootstrapped()
        try withTransaction { try reconcileWatches() }
    }
}
