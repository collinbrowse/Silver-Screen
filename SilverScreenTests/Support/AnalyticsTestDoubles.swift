//
//  AnalyticsTestDoubles.swift
//  SilverScreenTests
//
//  A spy for the analytics boundary and a sleeper the test opens by hand,
//  so batching can be observed without real delays.
//

import Foundation
import os
@testable import SilverScreen

/// Records every event in order. `send` is synchronous, so the list is complete
/// as soon as the repository call that sent it returns.
final class SpyAnalyticsClient: AnalyticsClient {
    private let recorded = OSAllocatedUnfairLock<[AnalyticsEvent]>(initialState: [])

    var events: [AnalyticsEvent] {
        recorded.withLock { $0 }
    }

    func send(_ event: AnalyticsEvent) {
        recorded.withLock { $0.append(event) }
    }
}

/// `sleep` suspends until `open()`; after that every sleep returns at once.
actor GateSleeper: Sleeper {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(seconds: TimeInterval) async throws {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// A throwaway UserDefaults suite name, so preference tests never touch the app's defaults.
func makeTestSuite() -> String {
    "test.analytics.\(UUID().uuidString)"
}
