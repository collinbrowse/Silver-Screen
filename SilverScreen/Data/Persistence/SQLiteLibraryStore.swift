//
//  SQLiteLibraryStore.swift
//  SilverScreen
//
//  library.sqlite implementation of LibraryStore. Domain-scoped replace mutations
//  keep list writes from touching annotations or TV progress (and vice versa).
//

import Foundation

actor SQLiteLibraryStore: LibraryStore {
    static let databaseFileName = "library.sqlite"
    static let jsonImportStampKey = "json_import"

    private let database: SQLiteDatabase
    private let listsJSONURL: URL
    private let annotationsJSONURL: URL
    private let tvWatchJSONURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var didBootstrap = false

    init(
        databaseURL: URL,
        listsJSONURL: URL,
        annotationsJSONURL: URL,
        tvWatchJSONURL: URL
    ) throws {
        self.database = try SQLiteDatabase(fileURL: databaseURL)
        self.listsJSONURL = listsJSONURL
        self.annotationsJSONURL = annotationsJSONURL
        self.tvWatchJSONURL = tvWatchJSONURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func applicationSupportDatabaseURL() throws -> URL {
        try AppSupportDirectory.fileURL(fileName: databaseFileName)
    }

    static func live() throws -> SQLiteLibraryStore {
        try SQLiteLibraryStore(
            databaseURL: applicationSupportDatabaseURL(),
            listsJSONURL: FileListsStore.applicationSupportURL(),
            annotationsJSONURL: FileAnnotationsStore.applicationSupportURL(),
            tvWatchJSONURL: FileTVWatchStore.applicationSupportURL()
        )
    }

    func bootstrap() async throws {
        guard !didBootstrap else { return }
        try migrateSchema()
        try await importLegacyJSONIfNeeded()
        didBootstrap = true
    }

    func fetchSnapshot() async throws -> LibrarySnapshot {
        try await ensureBootstrapped()
        var lists: [LibraryList] = []
        try database.collect(
            """
            SELECT id, name, segment, system_kind, sort, position
            FROM library_list
            WHERE deleted_at IS NULL
            ORDER BY position ASC, name ASC;
            """
        ) { statement in
            guard
                let idString = SQLiteBinding.columnText(statement, index: 0),
                let id = UUID(uuidString: idString),
                let name = SQLiteBinding.columnText(statement, index: 1),
                let segmentRaw = SQLiteBinding.columnText(statement, index: 2),
                let segment = LibrarySegment(rawValue: segmentRaw),
                let sortRaw = SQLiteBinding.columnText(statement, index: 4),
                let sort = LibrarySort(rawValue: sortRaw)
            else {
                return
            }
            let systemRaw = SQLiteBinding.columnText(statement, index: 3)
            let system = systemRaw.flatMap(SystemListKind.init(rawValue:))
            let position = SQLiteBinding.columnInt(statement, index: 5)
            lists.append(
                LibraryList(
                    id: id,
                    name: name,
                    segment: segment,
                    system: system,
                    sort: sort,
                    position: position
                )
            )
        }

        var mediaByKey: [String: (
            tmdbID: Int,
            kind: ListItemKind,
            title: String,
            imagePath: String?,
            releaseDate: Date?,
            genreNames: [String],
            voteAverage: Double,
            popularity: Double
        )] = [:]

        try database.collect(
            """
            SELECT item_key, tmdb_id, kind, title, image_path, release_date,
                   genre_names_json, vote_average, popularity
            FROM media_item
            WHERE deleted_at IS NULL;
            """
        ) { statement in
            guard
                let itemKey = SQLiteBinding.columnText(statement, index: 0),
                let kindRaw = SQLiteBinding.columnText(statement, index: 2),
                let kind = ListItemKind(rawValue: kindRaw),
                let title = SQLiteBinding.columnText(statement, index: 3)
            else {
                return
            }
            let genresJSON = SQLiteBinding.columnText(statement, index: 6) ?? "[]"
            let genres = (try? decoder.decode([String].self, from: Data(genresJSON.utf8))) ?? []
            mediaByKey[itemKey] = (
                tmdbID: SQLiteBinding.columnInt(statement, index: 1),
                kind: kind,
                title: title,
                imagePath: SQLiteBinding.columnText(statement, index: 4),
                releaseDate: LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 5)),
                genreNames: genres,
                voteAverage: SQLiteBinding.columnDouble(statement, index: 7),
                popularity: SQLiteBinding.columnDouble(statement, index: 8)
            )
        }

        var entries: [ListEntry] = []
        try database.collect(
            """
            SELECT list_id, item_key, added_at, position
            FROM list_membership
            WHERE deleted_at IS NULL
            ORDER BY position ASC, added_at DESC;
            """
        ) { statement in
            guard
                let listIDString = SQLiteBinding.columnText(statement, index: 0),
                let listID = UUID(uuidString: listIDString),
                let itemKey = SQLiteBinding.columnText(statement, index: 1),
                let media = mediaByKey[itemKey],
                let addedAtRaw = SQLiteBinding.columnText(statement, index: 2),
                let addedAt = LibrarySQLDate.decode(addedAtRaw)
            else {
                return
            }
            let draft = ListItemDraft(
                id: media.tmdbID,
                kind: media.kind,
                title: media.title,
                imagePath: media.imagePath,
                releaseDate: media.releaseDate,
                genreNames: media.genreNames,
                voteAverage: media.voteAverage,
                popularity: media.popularity
            )
            entries.append(
                ListEntry(
                    listID: listID,
                    draft: draft,
                    addedAt: addedAt,
                    position: SQLiteBinding.columnInt(statement, index: 3)
                )
            )
        }

        return LibrarySnapshot(lists: lists, entries: entries)
    }

    func fetchAnnotations() async throws -> [MediaAnnotation] {
        try await ensureBootstrapped()
        var records: [MediaAnnotation] = []
        try database.collect(
            """
            SELECT kind, subject_id, season_number, episode_number, score, note, watched_at
            FROM annotation
            WHERE deleted_at IS NULL;
            """
        ) { statement in
            guard
                let kindRaw = SQLiteBinding.columnText(statement, index: 0),
                let kind = AnnotationKind(rawValue: kindRaw)
            else {
                return
            }
            let key = AnnotationKey(
                kind: kind,
                subjectID: SQLiteBinding.columnInt(statement, index: 1),
                seasonNumber: SQLiteBinding.columnInt(statement, index: 2),
                episodeNumber: SQLiteBinding.columnInt(statement, index: 3)
            )
            let score = SQLiteBinding.columnIsNull(statement, index: 4)
                ? nil
                : SQLiteBinding.columnDouble(statement, index: 4)
            let note = SQLiteBinding.columnText(statement, index: 5)
            let watchedAt = LibrarySQLDate.decode(SQLiteBinding.columnText(statement, index: 6))
            let record = MediaAnnotation(key: key, score: score, note: note, watchedAt: watchedAt)
            if let normalized = record.normalized() {
                records.append(normalized)
            }
        }
        return records
    }

    func fetchTVWatchStates() async throws -> [TVSeriesWatchState] {
        try await ensureBootstrapped()
        var states: [TVSeriesWatchState] = []
        try database.collect(
            """
            SELECT series_id, next_up_season, next_up_episode, next_up_title, catalog_snapshot_json
            FROM tv_series_watch
            WHERE deleted_at IS NULL
            ORDER BY series_id ASC;
            """
        ) { statement in
            let seriesID = SQLiteBinding.columnInt(statement, index: 0)
            let nextUp: TVEpisodeRef?
            if SQLiteBinding.columnIsNull(statement, index: 1) || SQLiteBinding.columnIsNull(statement, index: 2) {
                nextUp = nil
            } else {
                nextUp = TVEpisodeRef(
                    seasonNumber: SQLiteBinding.columnInt(statement, index: 1),
                    episodeNumber: SQLiteBinding.columnInt(statement, index: 2)
                )
            }
            let nextUpTitle = SQLiteBinding.columnText(statement, index: 3)
            let catalog: [TVCatalogSeasonCount]?
            if let json = SQLiteBinding.columnText(statement, index: 4),
               let data = json.data(using: .utf8) {
                catalog = try? decoder.decode([TVCatalogSeasonCount].self, from: data)
            } else {
                catalog = nil
            }
            states.append(
                TVSeriesWatchState(
                    seriesID: seriesID,
                    completed: [],
                    nextUp: nextUp,
                    nextUpTitle: nextUpTitle,
                    catalogSnapshot: catalog
                )
            )
        }

        var completedBySeries: [Int: [TVEpisodeRef]] = [:]
        try database.collect(
            """
            SELECT series_id, season_number, episode_number
            FROM tv_episode_completed
            ORDER BY series_id ASC, season_number ASC, episode_number ASC;
            """
        ) { statement in
            let seriesID = SQLiteBinding.columnInt(statement, index: 0)
            let ref = TVEpisodeRef(
                seasonNumber: SQLiteBinding.columnInt(statement, index: 1),
                episodeNumber: SQLiteBinding.columnInt(statement, index: 2)
            )
            completedBySeries[seriesID, default: []].append(ref)
        }

        return states.map { state in
            TVSeriesWatchState(
                seriesID: state.seriesID,
                completed: completedBySeries[state.seriesID] ?? [],
                nextUp: state.nextUp,
                nextUpTitle: state.nextUpTitle,
                catalogSnapshot: state.catalogSnapshot
            )
        }
    }

    func apply(_ mutation: LibraryStoreMutation) async throws {
        try await ensureBootstrapped()
        switch mutation {
            case .replaceLists(let snapshot):
                try replaceLists(snapshot)
            case .replaceAnnotations(let records):
                try replaceAnnotations(records)
            case .replaceTVWatch(let states):
                try replaceTVWatch(states)
        }
    }

    // MARK: - Bootstrap / import

    private func ensureBootstrapped() async throws {
        if !didBootstrap {
            try await bootstrap()
        }
    }

    /// Applies each pending schema version in its own transaction.
    private func migrateSchema() throws {
        let hasMigrationsTable = try database.scalarInt(
            """
            SELECT COUNT(*) FROM sqlite_master
            WHERE type = 'table' AND name = 'schema_migrations';
            """
        ) > 0
        let applied: Int
        if hasMigrationsTable {
            applied = try database.scalarInt(
                "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;"
            )
        } else {
            applied = 0
        }
        guard applied < LibrarySchema.currentVersion else { return }
        for version in (applied + 1)...LibrarySchema.currentVersion {
            try withTransaction {
                for statement in try LibrarySchema.statements(for: version) {
                    try database.execute(statement)
                }
                try database.run(
                    "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?);"
                ) { statement in
                    SQLiteBinding.int(statement, index: 1, version)
                    SQLiteBinding.text(statement, index: 2, LibrarySQLDate.encode(Date()))
                }
            }
        }
    }

    /// Imports leftover JSON domains in one transaction, then stamps `json_import`.
    /// Empty domains are filled from JSON even if another domain already has SQL rows,
    /// so a crash between the old three-transaction writes cannot drop annotations/TV.
    private func importLegacyJSONIfNeeded() async throws {
        let stamp = try database.scalarText(
            "SELECT value FROM sync_state WHERE key = '\(Self.jsonImportStampKey)';"
        )
        if stamp != nil {
            renameImportedJSONFiles()
            return
        }

        let hasJSON =
            FileManager.default.fileExists(atPath: listsJSONURL.path)
            || FileManager.default.fileExists(atPath: annotationsJSONURL.path)
            || FileManager.default.fileExists(atPath: tvWatchJSONURL.path)
        guard hasJSON else {
            try setSyncState(Self.jsonImportStampKey, value: "none")
            return
        }

        let listCount = try database.scalarInt("SELECT COUNT(*) FROM library_list;")
        let annotationCount = try database.scalarInt("SELECT COUNT(*) FROM annotation;")
        let tvCount = try database.scalarInt("SELECT COUNT(*) FROM tv_series_watch;")
        if listCount > 0 && annotationCount > 0 && tvCount > 0 {
            renameImportedJSONFiles()
            try setSyncState(Self.jsonImportStampKey, value: "preferred_sqlite")
            return
        }

        let listsStore = FileListsStore(fileURL: listsJSONURL)
        let annotationsStore = FileAnnotationsStore(fileURL: annotationsJSONURL)
        let tvStore = FileTVWatchStore(fileURL: tvWatchJSONURL)
        let snapshot = try await listsStore.load()
        let annotations = try await annotationsStore.load()
        let tvStates = try await tvStore.load()

        try withTransaction {
            if listCount == 0 {
                try writeLists(snapshot)
            }
            if annotationCount == 0 {
                try writeAnnotations(annotations)
            }
            if tvCount == 0 {
                try writeTVWatch(tvStates)
            }
            try setSyncState(
                Self.jsonImportStampKey,
                value: LibrarySQLDate.encode(Date())
            )
        }
        renameImportedJSONFiles()
    }

    private func renameImportedJSONFiles() {
        for url in [listsJSONURL, annotationsJSONURL, tvWatchJSONURL] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let destination = url.appendingPathExtension("imported")
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: url, to: destination)
        }
    }

    private func setSyncState(_ key: String, value: String) throws {
        try database.run(
            """
            INSERT INTO sync_state (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """
        ) { statement in
            SQLiteBinding.text(statement, index: 1, key)
            SQLiteBinding.text(statement, index: 2, value)
        }
    }

    private func withTransaction(_ body: () throws -> Void) throws {
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Domain replace

    private func replaceLists(_ snapshot: LibrarySnapshot) throws {
        try withTransaction { try writeLists(snapshot) }
    }

    private func writeLists(_ snapshot: LibrarySnapshot) throws {
        let now = LibrarySQLDate.encode(Date())
        try database.execute("DELETE FROM list_membership;")
        try database.execute("DELETE FROM library_list;")
        try database.execute("DELETE FROM media_item;")

        for list in snapshot.lists {
            try database.run(
                """
                INSERT INTO library_list
                  (id, name, segment, system_kind, sort, position, updated_at, revision, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1, NULL);
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, list.id.uuidString)
                SQLiteBinding.text(statement, index: 2, list.name)
                SQLiteBinding.text(statement, index: 3, list.segment.rawValue)
                SQLiteBinding.text(statement, index: 4, list.system?.rawValue)
                SQLiteBinding.text(statement, index: 5, list.sort.rawValue)
                SQLiteBinding.int(statement, index: 6, list.position)
                SQLiteBinding.text(statement, index: 7, now)
            }
        }

        var seenMedia = Set<String>()
        for entry in snapshot.entries {
            if seenMedia.insert(entry.itemKey).inserted {
                let genresJSON = String(
                    data: (try? encoder.encode(entry.genreNames)) ?? Data("[]".utf8),
                    encoding: .utf8
                ) ?? "[]"
                try database.run(
                    """
                    INSERT INTO media_item
                      (item_key, tmdb_id, kind, title, image_path, release_date,
                       genre_names_json, vote_average, popularity, updated_at, revision, deleted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, NULL);
                    """
                ) { statement in
                    SQLiteBinding.text(statement, index: 1, entry.itemKey)
                    SQLiteBinding.int(statement, index: 2, entry.itemID)
                    SQLiteBinding.text(statement, index: 3, entry.kind.rawValue)
                    SQLiteBinding.text(statement, index: 4, entry.title)
                    SQLiteBinding.text(statement, index: 5, entry.imagePath)
                    SQLiteBinding.text(statement, index: 6, entry.releaseDate.map(LibrarySQLDate.encode))
                    SQLiteBinding.text(statement, index: 7, genresJSON)
                    SQLiteBinding.double(statement, index: 8, entry.voteAverage)
                    SQLiteBinding.double(statement, index: 9, entry.popularity)
                    SQLiteBinding.text(statement, index: 10, now)
                }
            }

            let membershipID = LibraryStableID.uuid(
                from: "membership:\(entry.listID.uuidString):\(entry.itemKey)"
            )
            try database.run(
                """
                INSERT INTO list_membership
                  (id, list_id, item_key, added_at, position, updated_at, revision, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, NULL);
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, membershipID.uuidString)
                SQLiteBinding.text(statement, index: 2, entry.listID.uuidString)
                SQLiteBinding.text(statement, index: 3, entry.itemKey)
                SQLiteBinding.text(statement, index: 4, LibrarySQLDate.encode(entry.addedAt))
                SQLiteBinding.int(statement, index: 5, entry.position)
                SQLiteBinding.text(statement, index: 6, now)
            }
        }
    }

    private func replaceAnnotations(_ records: [MediaAnnotation]) throws {
        try withTransaction { try writeAnnotations(records) }
    }

    private func writeAnnotations(_ records: [MediaAnnotation]) throws {
        let now = LibrarySQLDate.encode(Date())
        try database.execute("DELETE FROM annotation;")
        for record in records {
            guard let normalized = record.normalized() else { continue }
            let id = LibraryStableID.uuid(
                from: "annotation:\(normalized.key.kind.rawValue):\(normalized.key.subjectID):\(normalized.key.seasonNumber):\(normalized.key.episodeNumber)"
            )
            let itemKey = "\(normalized.key.kind.rawValue)-\(normalized.key.subjectID)-\(normalized.key.seasonNumber)-\(normalized.key.episodeNumber)"
            try database.run(
                """
                INSERT INTO annotation
                  (id, item_key, kind, subject_id, season_number, episode_number,
                   score, note, watched_at, updated_at, revision, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, NULL);
                """
            ) { statement in
                SQLiteBinding.text(statement, index: 1, id.uuidString)
                SQLiteBinding.text(statement, index: 2, itemKey)
                SQLiteBinding.text(statement, index: 3, normalized.key.kind.rawValue)
                SQLiteBinding.int(statement, index: 4, normalized.key.subjectID)
                SQLiteBinding.int(statement, index: 5, normalized.key.seasonNumber)
                SQLiteBinding.int(statement, index: 6, normalized.key.episodeNumber)
                SQLiteBinding.double(statement, index: 7, normalized.score)
                SQLiteBinding.text(statement, index: 8, normalized.note)
                SQLiteBinding.text(statement, index: 9, normalized.watchedAt.map(LibrarySQLDate.encode))
                SQLiteBinding.text(statement, index: 10, now)
            }
        }
    }

    private func replaceTVWatch(_ states: [TVSeriesWatchState]) throws {
        try withTransaction { try writeTVWatch(states) }
    }

    private func writeTVWatch(_ states: [TVSeriesWatchState]) throws {
        let now = LibrarySQLDate.encode(Date())
        try database.execute("DELETE FROM tv_episode_completed;")
        try database.execute("DELETE FROM tv_series_watch;")
        for state in states {
            let catalogJSON: String?
            if let catalog = state.catalogSnapshot,
               let data = try? encoder.encode(catalog) {
                catalogJSON = String(data: data, encoding: .utf8)
            } else {
                catalogJSON = nil
            }
            try database.run(
                """
                INSERT INTO tv_series_watch
                  (series_id, next_up_season, next_up_episode, next_up_title,
                   catalog_snapshot_json, updated_at, revision, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, NULL);
                """
            ) { statement in
                SQLiteBinding.int(statement, index: 1, state.seriesID)
                SQLiteBinding.int(statement, index: 2, state.nextUp?.seasonNumber)
                SQLiteBinding.int(statement, index: 3, state.nextUp?.episodeNumber)
                SQLiteBinding.text(statement, index: 4, state.nextUpTitle)
                SQLiteBinding.text(statement, index: 5, catalogJSON)
                SQLiteBinding.text(statement, index: 6, now)
            }
            for episode in state.completed {
                try database.run(
                    """
                    INSERT INTO tv_episode_completed
                      (series_id, season_number, episode_number)
                    VALUES (?, ?, ?);
                    """
                ) { statement in
                    SQLiteBinding.int(statement, index: 1, state.seriesID)
                    SQLiteBinding.int(statement, index: 2, episode.seasonNumber)
                    SQLiteBinding.int(statement, index: 3, episode.episodeNumber)
                }
            }
        }
    }
}
