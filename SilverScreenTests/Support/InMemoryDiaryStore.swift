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
    private var loadError: Error?
    private var saveError: Error?

    init(entries: [DiaryEntry] = []) {
        self.entries = entries
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

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }
}
