//
//  SentryBootstrap.swift
//  SilverScreen
//
//  Starts Sentry when a DSN is present. Empty DSN keeps local Debug quiet.
//

import Foundation
import os
import Sentry

/// Wires crash reporting and release health using the shipping marketing+build identity.
enum SentryBootstrap {
    private static let started = OSAllocatedUnfairLock(initialState: false)

    /// True after a successful `start` with a real DSN.
    static var isStarted: Bool {
        started.withLock { $0 }
    }

    /// Same shape as `testflight/<marketing>+<build>` without the prefix.
    static func releaseName(marketing: String, build: String) -> String {
        "\(marketing)+\(build)"
    }

    /// Reads `SentryDSN` from an Info.plist dictionary. Missing, empty, or unsubstituted `$(…)` means “do not start.”
    static func resolvedDSN(infoDictionary: [String: Any]) -> String? {
        guard let raw = infoDictionary["SentryDSN"] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }

    /// Marketing and build from Info.plist keys (`CFBundleShortVersionString` / `CFBundleVersion`).
    static func releaseName(infoDictionary: [String: Any]) -> String? {
        let marketing = infoDictionary["CFBundleShortVersionString"] as? String
        let build = infoDictionary["CFBundleVersion"] as? String
        guard let marketing, let build,
              !marketing.isEmpty, !build.isEmpty
        else {
            return nil
        }
        return releaseName(marketing: marketing, build: build)
    }

    /// Starts the SDK when a DSN is configured. Safe to call once at launch.
    static func start(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        guard let dsn = resolvedDSN(infoDictionary: info) else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            if let release = releaseName(infoDictionary: info) {
                options.releaseName = release
            }
            options.enableAutoSessionTracking = true
            options.sendDefaultPii = false
            #if DEBUG
            options.tracesSampleRate = 0
            #else
            options.tracesSampleRate = 0.2
            #endif
        }

        started.withLock { $0 = true }
    }

    /// Forwards a developer-authored technical error already logged via `AppLogging`.
    /// No-op when Sentry was never started (missing DSN).
    static func captureError(_ message: String, category: LogCategory) {
        guard isStarted else {
            return
        }
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: message)
        event.tags = ["category": category.rawValue]
        SentrySDK.capture(event: event)
    }
}
