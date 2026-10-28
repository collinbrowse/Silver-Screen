//
//  DiaryRepository.swift
//  SilverScreen
//
//  Logged watches. Every save hands the whole diary to the store, which diffs it
//  against the stored rows in one transaction (the same pattern as annotations).
//  Writes are serialized so two saves cannot clobber each other.
//

import Foundation

actor DiaryRepository {
    private let store: any DiaryStore
    private let logger: any AppLogging
    private var cached: [DiaryEntry]?
    private var loadTask: Task<[DiaryEntry], Error>?
    private var writeBarrier: Task<Void, Never>?

    init(store: any DiaryStore, logger: any AppLogging) {
        self.store = store
        self.logger = logger
    }

    /// Every entry, newest watch first; entries on the same day put the latest log first.
    func entries() async throws -> [DiaryEntry] {
        Self.sorted(try await loadCache())
    }

    /// Entries for one title, newest watch first.
    func entries(for subject: DiarySubject) async throws -> [DiaryEntry] {
        try await entries().filter { $0.subject == subject }
    }

    /// Episodes checked off in TV progress, newest first. Read fresh every time rather
    /// than cached, because the TV screens write progress without going through here.
    func episodeWatches() async throws -> [EpisodeWatch] {
        do {
            return try await store.loadEpisodeWatches()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Diary episode history load failed", category: .persistence)
            throw AppError.persistence
        }
    }

    /// Episode watches for one series, newest first.
    func episodeWatches(seriesID: Int) async throws -> [EpisodeWatch] {
        try await episodeWatches().filter { $0.seriesID == seriesID }
    }

    /// Inserts `entry`, or replaces the entry with the same id. Returns what was stored
    /// (normalized: blank review and tags dropped, invalid score cleared).
    @discardableResult
    func save(_ entry: DiaryEntry) async throws -> DiaryEntry {
        guard entry.subject.kind != .person else {
            logger.error("Rejected a diary entry for a person", category: .persistence)
            throw AppError.persistence
        }
        let normalized = entry.normalized()
        return try await serializeWrite { [self] in
            var entries = try await loadCache()
            if let index = entries.firstIndex(where: { $0.id == normalized.id }) {
                guard entries[index] != normalized else { return normalized }
                entries[index] = normalized
            } else {
                entries.append(normalized)
            }
            try await persist(entries)
            return normalized
        }
    }

    /// Removes the entry. The store keeps a tombstone so the removal can sync later.
    /// No-op when the id is not stored.
    func delete(id: UUID) async throws {
        try await serializeWrite { [self] in
            var entries = try await loadCache()
            let before = entries.count
            entries.removeAll { $0.id == id }
            guard entries.count != before else { return }
            try await persist(entries)
        }
    }

    static func sorted(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.watchedOn != rhs.watchedOn {
                return lhs.watchedOn > rhs.watchedOn
            }
            if lhs.loggedAt != rhs.loggedAt {
                return lhs.loggedAt > rhs.loggedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
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

    private func loadCache() async throws -> [DiaryEntry] {
        if let cached {
            return cached
        }
        if let loadTask {
            return try await loadTask.value
        }
        let task = Task { try await self.performLoad() }
        loadTask = task
        do {
            let entries = try await task.value
            loadTask = nil
            return entries
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func performLoad() async throws -> [DiaryEntry] {
        do {
            let entries = try await store.load()
            cached = entries
            return entries
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Diary load failed", category: .persistence)
            throw AppError.persistence
        }
    }

    private func persist(_ entries: [DiaryEntry]) async throws {
        do {
            try await store.save(entries)
            cached = entries
        } catch {
            logger.error("Diary save failed", category: .persistence)
            throw AppError.persistence
        }
    }
}
