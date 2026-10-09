//
//  TVWatchStore.swift
//  TheSilverScreen
//
//  Persistence seam for episode watch progress. Tests use an in-memory store.
//

import Foundation

protocol TVWatchStore: Sendable {
    func load() async throws -> [TVSeriesWatchState]
    func save(_ states: [TVSeriesWatchState]) async throws
}
