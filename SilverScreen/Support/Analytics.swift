//
//  Analytics.swift
//  SilverScreen
//
//  Anonymous product events: a handful of counts that say whether people get
//  value from the app, never what they watch. The TelemetryDeck sender lives in
//  `Data/Networking/TelemetryDeckClient.swift`. See OBSERVABILITY.md.
//

import Foundation
import Observation

/// The only product events the app sends. Each one is a bare count: no titles,
/// list names, ratings, or notes ride along. Raw values follow TelemetryDeck's
/// `Scope.eventName` convention and are what the dashboard shows.
enum AnalyticsEvent: String, Sendable, CaseIterable {
    /// Onboarding's last step was finished (not skipped). Sent from `OnboardingGate.finish()`.
    case onboardingFinished = "Onboarding.finished"
    /// The library went from no ratings to one.
    case firstRating = "Library.firstRatingSaved"
    /// A custom list was created.
    case listCreated = "Library.listCreated"
    /// A movie or show was put on Watchlist.
    case titleAddedToWatchlist = "Library.titleAddedToWatchlist"
}

/// Fire-and-forget event sink. `send` returns at once, never throws, and never
/// blocks the caller, so repositories and view models can call it inline.
/// This is a network boundary, so tests substitute a spy.
protocol AnalyticsClient: Sendable {
    func send(_ event: AnalyticsEvent)
}

/// Sends nothing. Used when no TelemetryDeck app ID is configured, for demo
/// launches, and as the default for repositories built in tests.
struct DisabledAnalytics: AnalyticsClient {
    func send(_ event: AnalyticsEvent) {}
}

/// The person's analytics choice and the random install identifier, both in UserDefaults.
/// Sharing is on by default; turning it off also forgets the identifier, so turning it
/// back on counts as a new, unrelated install.
struct AnalyticsPreferences: Sendable {
    static let optedOutKey = "analyticsOptedOut"
    static let installIDKey = "analyticsInstallID"

    /// The UserDefaults suite, or nil for `.standard`. A name rather than the instance,
    /// because `UserDefaults` is not `Sendable` and the sender reads this off the main actor.
    let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    var isSharingEnabled: Bool {
        !defaults.bool(forKey: Self.optedOutKey)
    }

    func setSharingEnabled(_ enabled: Bool) {
        defaults.set(!enabled, forKey: Self.optedOutKey)
        if !enabled {
            defaults.removeObject(forKey: Self.installIDKey)
        }
    }

    /// A random UUID made on first use. It identifies an install, not a person:
    /// it is not derived from the device, an account, or anything the person typed.
    func installID() -> String {
        if let existing = defaults.string(forKey: Self.installIDKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Self.installIDKey)
        return fresh
    }
}

/// Backs the Settings toggle. Writes through to `AnalyticsPreferences`, which the
/// sender reads before every event and again before every upload.
@Observable
@MainActor
final class AnalyticsSharing {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            preferences.setSharingEnabled(isEnabled)
        }
    }

    @ObservationIgnored private let preferences: AnalyticsPreferences

    init(preferences: AnalyticsPreferences) {
        self.preferences = preferences
        self.isEnabled = preferences.isSharingEnabled
    }
}
