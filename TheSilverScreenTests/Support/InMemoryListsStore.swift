//
//  InMemoryListsStore.swift
//  TheSilverScreenTests
//

import Foundation
@testable import TheSilverScreen

actor InMemoryListsStore: ListsStore {
    private var snapshot: LibrarySnapshot
    var loadError: Error?
    var saveError: Error?

    init(snapshot: LibrarySnapshot = .empty) {
        self.snapshot = snapshot
    }

    func load() async throws -> LibrarySnapshot {
        if let loadError {
            throw loadError
        }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        if let saveError {
            throw saveError
        }
        self.snapshot = snapshot
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }
}
