//
//  InMemoryTVWatchStore.swift
//  TheSilverScreenTests
//

import Foundation
@testable import TheSilverScreen

actor InMemoryTVWatchStore: TVWatchStore {
    private var states: [TVSeriesWatchState]
    var loadError: Error?
    var saveError: Error?

    init(states: [TVSeriesWatchState] = []) {
        self.states = states
    }

    func load() async throws -> [TVSeriesWatchState] {
        if let loadError {
            throw loadError
        }
        return states
    }

    func save(_ states: [TVSeriesWatchState]) async throws {
        if let saveError {
            throw saveError
        }
        self.states = states
    }
}
