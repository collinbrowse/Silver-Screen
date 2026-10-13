//
//  TVWatchStore.swift
//  SilverScreen
//
//  Persistence seam for episode watch progress. Production uses a LibraryStore
//  adapter over library.sqlite; tests use an in-memory store.
//

import Foundation

protocol TVWatchStore: Sendable {
    func load() async throws -> [TVSeriesWatchState]
    func save(_ states: [TVSeriesWatchState]) async throws
}
