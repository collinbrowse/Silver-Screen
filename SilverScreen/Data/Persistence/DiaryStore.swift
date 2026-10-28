//
//  DiaryStore.swift
//  SilverScreen
//
//  Disk boundary for diary entries. Production uses a LibraryStore adapter over
//  library.sqlite; tests substitute an in-memory store.
//

import Foundation

protocol DiaryStore: Sendable {
    func load() async throws -> [DiaryEntry]
    func save(_ entries: [DiaryEntry]) async throws
    /// Episodes checked off in TV progress, which the diary lists beside its entries;
    /// one show's when `seriesID` is set.
    func loadEpisodeWatches(seriesID: Int?) async throws -> [EpisodeWatch]
}

/// `DiaryStore` over the shared library store, so a diary save is one diffed,
/// domain-scoped transaction like lists, annotations, and TV progress.
actor LibraryDiaryStoreAdapter: DiaryStore {
    private let library: any LibraryStore

    init(library: any LibraryStore) {
        self.library = library
    }

    func load() async throws -> [DiaryEntry] {
        try await library.fetchDiaryEntries()
    }

    func save(_ entries: [DiaryEntry]) async throws {
        try await library.apply(.replaceDiary(entries))
    }

    func loadEpisodeWatches(seriesID: Int?) async throws -> [EpisodeWatch] {
        try await library.fetchEpisodeWatches(seriesID: seriesID)
    }
}
