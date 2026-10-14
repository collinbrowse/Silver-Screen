//
//  DemoMode.swift
//  SilverScreen
//
//  Launch-time switch for marketing captures (App Store screenshots and website
//  videos). Read from the process environment in Debug builds only, so a shipped
//  build always opens the real library.
//

import Foundation

/// How a marketing capture launch differs from a normal one: a throwaway library
/// seeded from `marketing/titles.json`, and an optional tab and screen to open on.
struct DemoMode: Sendable, Equatable {
    /// `1` turns demo mode on. Nothing else is read without it.
    static let enabledKey = "SS_DEMO_MODE"
    /// Absolute path to a JSON file with a top-level `library` object. See `DemoLibrarySeed`.
    static let seedKey = "SS_DEMO_SEED"
    /// A `RouterSnapshot` as JSON, used in place of the saved navigation state.
    static let routeKey = "SS_DEMO_ROUTE"

    let seedURL: URL?
    let routerSnapshot: RouterSnapshot?

    /// Returns nil unless `SS_DEMO_MODE=1`. A route that does not decode is ignored
    /// so the capture still launches on Browse instead of failing to start.
    static func from(environment: [String: String]) -> DemoMode? {
        guard environment[enabledKey] == "1" else { return nil }
        let seedURL = environment[seedKey]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let routerSnapshot = environment[routeKey]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(RouterSnapshot.self, from: $0) }
        return DemoMode(seedURL: seedURL, routerSnapshot: routerSnapshot)
    }

    /// The environment of this process in Debug builds; always nil in Release.
    static func current() -> DemoMode? {
        #if DEBUG
        from(environment: ProcessInfo.processInfo.environment)
        #else
        nil
        #endif
    }

    /// A library in a fresh temporary directory, so a capture never reads or
    /// writes the real one and every launch starts from the same seed.
    func libraryStore() throws -> SQLiteLibraryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilverScreenDemo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteLibraryStore(
            databaseURL: directory.appendingPathComponent(SQLiteLibraryStore.databaseFileName),
            listsJSONURL: directory.appendingPathComponent("lists.json"),
            annotationsJSONURL: directory.appendingPathComponent("annotations.json"),
            tvWatchJSONURL: directory.appendingPathComponent("tv-progress.json")
        )
    }
}
