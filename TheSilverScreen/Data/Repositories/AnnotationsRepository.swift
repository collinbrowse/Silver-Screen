//
//  AnnotationsRepository.swift
//  TheSilverScreen
//
//  Personal scores and notes. A note always rides with a score going forward:
//  `save` writes both; `deleteNote` clears only the note; `clear` removes the
//  whole row. Legacy note-only rows still load from disk but cannot be created
//  here. Writes are serialized so two saves cannot clobber each other.
//

import Foundation

actor AnnotationsRepository {
    private let store: any AnnotationsStore
    private let logger: any AppLogging
    private var cached: [MediaAnnotation]?
    private var loadTask: Task<[MediaAnnotation], Error>?
    private var writeBarrier: Task<Void, Never>?

    init(store: any AnnotationsStore, logger: any AppLogging) {
        self.store = store
        self.logger = logger
    }

    /// Formatted scores for every saved title, with the day each score was chosen.
    /// An unreadable file yields an empty map.
    func formattedScores() async -> [AnnotationKey: SavedUserScore] {
        let records = (try? await loadCache()) ?? []
        var scores: [AnnotationKey: SavedUserScore] = [:]
        for record in records {
            if let score = record.score {
                scores[record.key] = SavedUserScore(
                    formatted: UserScore.formatted(score),
                    ratedOn: record.watchedAt.map { DisplayDate.localDay($0) }
                )
            }
        }
        return scores
    }

    func annotation(for key: AnnotationKey) async throws -> MediaAnnotation? {
        let records = try await loadCache()
        return records.first { $0.key == key }
    }

    /// Every stored score and note. An unreadable file yields an empty list.
    func saved() async -> [MediaAnnotation] {
        (try? await loadCache()) ?? []
    }

    /// Stores a half-point score and optional note in one write.
    /// Whitespace clears the note. The watched day is recorded only the first time.
    @discardableResult
    func save(
        score: Double,
        note: String,
        for key: AnnotationKey,
        at watchedAt: Date = Date()
    ) async throws -> MediaAnnotation {
        guard UserScore.isValid(score) else {
            logger.error("Rejected user score outside 0.5...10", category: .persistence)
            throw AppError.persistence
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = trimmed.isEmpty ? nil : trimmed
        return try await serializeWrite { [self] in
            try await upsert(key: key) { record in
                record.score = score
                record.note = cleanNote
                if record.watchedAt == nil {
                    record.watchedAt = watchedAt
                }
            }
        }
    }

    /// Stores a half-point score and leaves any existing note in place.
    /// The watched day is recorded only the first time a score or note is saved.
    /// Does not create note-only rows; a note already on disk (legacy) is kept.
    @discardableResult
    func saveScore(_ score: Double, for key: AnnotationKey, at watchedAt: Date = Date()) async throws -> MediaAnnotation {
        guard UserScore.isValid(score) else {
            logger.error("Rejected user score outside 0.5...10", category: .persistence)
            throw AppError.persistence
        }
        return try await serializeWrite { [self] in
            try await upsert(key: key) { record in
                record.score = score
                if record.watchedAt == nil {
                    record.watchedAt = watchedAt
                }
            }
        }
    }

    /// Removes the note and leaves the score. Returns nil when the title has no score left.
    /// Legacy note-only rows are removed entirely.
    @discardableResult
    func deleteNote(for key: AnnotationKey) async throws -> MediaAnnotation? {
        try await serializeWrite { [self] in
            try await writeNote(nil, for: key)
        }
    }

    /// Removes the score and note for `key`. No-op when nothing is stored.
    func clear(for key: AnnotationKey) async throws {
        try await serializeWrite { [self] in
            var records = try await loadCache()
            let before = records.count
            records.removeAll { $0.key == key }
            guard records.count != before else { return }
            try await persist(records)
        }
    }

    /// Puts `record` back for `key`, or removes the row when `record` is nil.
    /// Used to roll back a successful annotation write when a dependent save fails.
    func restore(_ record: MediaAnnotation?, for key: AnnotationKey) async throws {
        try await serializeWrite { [self] in
            var records = try await loadCache()
            if let index = records.firstIndex(where: { $0.key == key }) {
                if let record {
                    records[index] = record
                } else {
                    records.remove(at: index)
                }
            } else if let record {
                records.append(record)
            }
            try await persist(records)
        }
    }

    /// Updates the note on an existing row. Never creates a note-only record.
    private func writeNote(_ note: String?, for key: AnnotationKey) async throws -> MediaAnnotation? {
        var records = try await loadCache()
        guard let index = records.firstIndex(where: { $0.key == key }) else {
            return nil
        }
        var record = records[index]
        record.note = note
        guard record.normalized() != nil else {
            records.remove(at: index)
            try await persist(records)
            return nil
        }
        records[index] = record
        try await persist(records)
        return record
    }

    private func upsert(
        key: AnnotationKey,
        mutate: (inout MediaAnnotation) -> Void
    ) async throws -> MediaAnnotation {
        var records = try await loadCache()
        if let index = records.firstIndex(where: { $0.key == key }) {
            var record = records[index]
            mutate(&record)
            records[index] = record
            try await persist(records)
            return record
        }
        var record = MediaAnnotation(key: key, score: nil, note: nil, watchedAt: nil)
        mutate(&record)
        records.append(record)
        try await persist(records)
        return record
    }

    private func serializeWrite<T: Sendable>(
        _ work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let previous = writeBarrier
        let task = Task<T, Error> {
            _ = await previous?.value
            try Task.checkCancellation()
            return try await work()
        }
        writeBarrier = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func loadCache() async throws -> [MediaAnnotation] {
        if let cached {
            return cached
        }
        if let loadTask {
            return try await loadTask.value
        }
        let task = Task { try await self.performLoad() }
        loadTask = task
        do {
            let records = try await task.value
            loadTask = nil
            return records
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func performLoad() async throws -> [MediaAnnotation] {
        do {
            let records = try await store.load()
            cached = records
            return records
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Annotations load failed", category: .persistence)
            throw AppError.persistence
        }
    }

    private func persist(_ records: [MediaAnnotation]) async throws {
        do {
            try await store.save(records)
            cached = records
        } catch {
            logger.error("Annotations save failed", category: .persistence)
            throw AppError.persistence
        }
    }
}
