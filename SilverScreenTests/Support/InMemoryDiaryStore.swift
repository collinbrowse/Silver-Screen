//
//  InMemoryDiaryStore.swift
//  SilverScreenTests
//

import Foundation
@testable import SilverScreen

/// In-memory `DiaryStore` that can be told to fail loads or saves.
actor InMemoryDiaryStore: DiaryStore {
    private(set) var entries: [DiaryEntry]
    private(set) var saveCount = 0
    private var episodeWatches: [EpisodeWatch]
    private var loadError: Error?
    private var episodeLoadError: Error?
    private var saveError: Error?

    init(entries: [DiaryEntry] = [], episodeWatches: [EpisodeWatch] = []) {
        self.entries = entries
        self.episodeWatches = episodeWatches
    }

    func load() async throws -> [DiaryEntry] {
        if let loadError {
            throw loadError
        }
        return entries
    }

    func save(_ entries: [DiaryEntry]) async throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        self.entries = entries
    }

    func loadEpisodeWatches(seriesID: Int?) async throws -> [EpisodeWatch] {
        if let episodeLoadError {
            throw episodeLoadError
        }
        guard let seriesID else { return episodeWatches }
        return episodeWatches.filter { $0.seriesID == seriesID }
    }

    func setEpisodeLoadError(_ error: Error?) {
        episodeLoadError = error
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }
}
