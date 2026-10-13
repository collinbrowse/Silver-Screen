//
//  AnnotationsStore.swift
//  SilverScreen
//
//  Disk boundary for personal scores and notes. Production uses a LibraryStore
//  adapter over library.sqlite; tests substitute an in-memory store.
//

import Foundation

protocol AnnotationsStore: Sendable {
    func load() async throws -> [MediaAnnotation]
    func save(_ records: [MediaAnnotation]) async throws
}
