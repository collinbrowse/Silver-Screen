//
//  ListsStore.swift
//  TheSilverScreen
//
//  Disk boundary for the personal library. Tests substitute an in-memory store.
//  The file is lists.json. favorites.json is not read or imported.
//

import Foundation

protocol ListsStore: Sendable {
    func load() async throws -> LibrarySnapshot
    func save(_ snapshot: LibrarySnapshot) async throws
}
