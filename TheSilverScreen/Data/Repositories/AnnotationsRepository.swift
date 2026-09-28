//
//  AnnotationsRepository.swift
//  TheSilverScreen
//
//  Personal scores and notes. A score and a note for the same title update independently.
//  A blank note is stored as absent. Writes are serialized so two saves cannot clobber each other.
//

import Foundation

actor AnnotationsRepository {
    private let store: any AnnotationsStore
    private let logger: any AppLogging
    private var cached: [MediaAnnotation]?
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

    /// Stores a half-point score and leaves any existing note in place.
    /// The watched day is recorded only the first time a score or note is saved.
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

    /// Stores a note. Whitespace clears the note. Returns nil when the title has neither a score nor a note.
    @discardableResult
    func saveNote(_ note: String, for key: AnnotationKey, at notedAt: Date = Date()) async throws -> MediaAnnotation? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await serializeWrite { [self] in
            try await writeNote(trimmed.isEmpty ? nil : trimmed, for: key, at: notedAt)
        }
    }

    /// Removes the note and leaves the score. Returns nil when the title has no score left.
    @discardableResult
    func deleteNote(for key: AnnotationKey) async throws -> MediaAnnotation? {
        try await serializeWrite { [self] in
            try await writeNote(nil, for: key, at: Date())
        }
    }

    private func writeNote(_ note: String?, for key: AnnotationKey, at notedAt: Date) async throws -> MediaAnnotation? {
        var records = try await loadCache()
        if let index = records.firstIndex(where: { $0.key == key }) {
            var record = records[index]
            record.note = note
            if note != nil, record.watchedAt == nil {
                record.watchedAt = notedAt
            }
            guard record.normalized() != nil else {
                records.remove(at: index)
                try await persist(records)
                return nil
            }
            records[index] = record
            try await persist(records)
            return record
        }
        guard let note else { return nil }
        let record = MediaAnnotation(key: key, score: nil, note: note, watchedAt: notedAt)
        records.append(record)
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
            return try await work()
        }
        writeBarrier = Task { _ = try? await task.value }
        return try await task.value
    }

    private func loadCache() async throws -> [MediaAnnotation] {
        if let cached {
            return cached
        }
        do {
            let records = try await store.load()
            cached = records
            return records
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
