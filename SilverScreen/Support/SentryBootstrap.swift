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
    ///
    /// xcconfig treats `//` as a comment, so Secrets use `https:/$()/…`. If `$()` survives into Info.plist,
    /// strip it so the SDK gets a real `https://…` DSN.
    static func resolvedDSN(infoDictionary: [String: Any]) -> String? {
        guard let raw = infoDictionary["SentryDSN"] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$()", with: "")
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        guard trimmed.hasPrefix("https://"), trimmed.contains("@") else {
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
            configure(options, dsn: dsn, infoDictionary: info)
        }

        started.withLock { $0 = true }
    }

    /// Every option the app sets, kept apart from `start` so tests can check them.
    static func configure(_ options: Options, dsn: String, infoDictionary info: [String: Any]) {
        options.dsn = dsn
        if let release = releaseName(infoDictionary: info) {
            options.releaseName = release
        }
        options.enableAutoSessionTracking = true
        options.sendDefaultPii = false
        // A failed-request event carries the request's query string, and 5xx responses
        // are already reported through `AppLogging` with the path only.
        options.enableCaptureFailedRequests = false
        options.beforeBreadcrumb = { scrubbed($0) }
        options.beforeSendSpan = { scrubbed($0) }
        #if DEBUG
        options.tracesSampleRate = 0
        #else
        options.tracesSampleRate = 0.2
        #endif
    }

    /// Keys where the SDK copies a request's query string and fragment. Search requests
    /// carry what the user typed in `query`, which observability.mdc never sends.
    static let requestURLDataKeys = ["http.query", "http.fragment"]

    /// Drops the query and fragment from an HTTP breadcrumb. Other breadcrumbs pass through.
    static func scrubbed(_ breadcrumb: Breadcrumb) -> Breadcrumb {
        guard var data = breadcrumb.data else { return breadcrumb }
        for key in requestURLDataKeys {
            data[key] = nil
        }
        breadcrumb.data = data
        return breadcrumb
    }

    /// Drops the query and fragment from a network span.
    static func scrubbed(_ span: any Span) -> any Span {
        for key in requestURLDataKeys {
            span.removeData(key: key)
        }
        return span
    }

    /// Sends in-app feedback. The release tag carries the version and build.
    /// Returns false when Sentry was never started (missing DSN), so the screen can say so.
    static func sendFeedback(message: String, email: String?) -> Bool {
        guard isStarted else {
            return false
        }
        SentrySDK.capture(feedback: SentryFeedback(message: message, name: nil, email: email, source: .custom))
        return true
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
