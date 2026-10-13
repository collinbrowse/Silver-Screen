//
//  LibraryStoreAdapters.swift
//  SilverScreen
//
//  Narrow ListsStore / AnnotationsStore / TVWatchStore facades over LibraryStore
//  so repositories keep their existing seams while writes stay domain-scoped.
//

import Foundation

actor LibraryListsStoreAdapter: ListsStore {
    private let library: any LibraryStore

    init(library: any LibraryStore) {
        self.library = library
    }

    func load() async throws -> LibrarySnapshot {
        try await library.fetchSnapshot()
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        try await library.apply(.replaceLists(snapshot))
    }
}

actor LibraryAnnotationsStoreAdapter: AnnotationsStore {
    private let library: any LibraryStore

    init(library: any LibraryStore) {
        self.library = library
    }

    func load() async throws -> [MediaAnnotation] {
        try await library.fetchAnnotations()
    }

    func save(_ records: [MediaAnnotation]) async throws {
        try await library.apply(.replaceAnnotations(records))
    }
}

actor LibraryTVWatchStoreAdapter: TVWatchStore {
    private let library: any LibraryStore

    init(library: any LibraryStore) {
        self.library = library
    }

    func load() async throws -> [TVSeriesWatchState] {
        try await library.fetchTVWatchStates()
    }

    func save(_ states: [TVSeriesWatchState]) async throws {
        try await library.apply(.replaceTVWatch(states))
    }
}
