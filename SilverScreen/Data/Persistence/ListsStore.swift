//
//  ListsStore.swift
//  SilverScreen
//
//  Disk boundary for the personal library. Production uses a LibraryStore
//  adapter over library.sqlite; tests substitute an in-memory store.
//

import Foundation

protocol ListsStore: Sendable {
    func load() async throws -> LibrarySnapshot
    func save(_ snapshot: LibrarySnapshot) async throws
}
