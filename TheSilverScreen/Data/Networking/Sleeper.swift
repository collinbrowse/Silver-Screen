//
//  Sleeper.swift
//  TheSilverScreen
//
//  Clock seam for retry backoff. Tests inject a no-op so retries stay fast.
//

import Foundation

protocol Sleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct TaskSleeper: Sleeper {
    func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

struct NoopSleeper: Sleeper {
    func sleep(seconds: TimeInterval) async throws {}
}
