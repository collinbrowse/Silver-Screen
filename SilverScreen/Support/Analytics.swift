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
import os

/// The only product events the app sends. Each one is a bare count: no titles,
/// list names, ratings, or notes ride along. Raw values follow TelemetryDeck's
/// `Scope.eventName` convention and are what the dashboard shows. The two
/// `TelemetryDeck.` types are the names its SDK uses, so the built-in session,
/// active-user, and retention charts read them.
enum AnalyticsEvent: String, Sendable, CaseIterable {
    /// The app opened, or came back after `AnalyticsSessionTracker.idleThreshold` away.
    /// Sent by `AnalyticsSessionTracker`.
    case sessionStarted = "TelemetryDeck.Session.started"
    /// The first session after install (or after turning sharing back on). The sender
    /// adds it in front of that session's `sessionStarted`; nothing sends it directly.
    case newInstallDetected = "TelemetryDeck.Acquisition.newInstallDetected"
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
    static let firstSessionDayKey = "analyticsFirstSessionDay"
    static let sessionCountKey = "analyticsSessionCount"
    static let daysUsedKey = "analyticsDaysUsed"
    /// Everything that ties this install's signals together over time. Opting out removes all of it.
    static let identityKeys = [installIDKey, firstSessionDayKey, sessionCountKey, daysUsedKey]
    /// Days kept for "distinct days used", about a year and a month.
    static let maxDaysKept = 400

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
            for key in Self.identityKeys {
                defaults.removeObject(forKey: key)
            }
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

/// Session and day counts, so signals can carry TelemetryDeck's retention fields.
/// Date and calendar are parameters so tests can fix them.
extension AnalyticsPreferences {
    /// Counts a new session on `date` and returns the retention numbers after it.
    /// `isNewInstall` is true for the first session this install records.
    func recordSessionStart(at date: Date, calendar: Calendar) -> (retention: AnalyticsRetention, isNewInstall: Bool) {
        let today = AnalyticsRetention.day(date, calendar: calendar)
        let isNewInstall = defaults.string(forKey: Self.firstSessionDayKey) == nil
        if isNewInstall {
            defaults.set(today, forKey: Self.firstSessionDayKey)
        }
        defaults.set(defaults.integer(forKey: Self.sessionCountKey) + 1, forKey: Self.sessionCountKey)
        var days = defaults.stringArray(forKey: Self.daysUsedKey) ?? []
        if !days.contains(today) {
            days.append(today)
            defaults.set(Array(days.suffix(Self.maxDaysKept)), forKey: Self.daysUsedKey)
        }
        let retention = retention(at: date, calendar: calendar)
            ?? AnalyticsRetention(firstSessionDay: today, totalSessions: 1, distinctDaysUsed: 1, distinctDaysUsedLastMonth: 1)
        return (retention, isNewInstall)
    }

    /// The retention numbers as of `date`, or nil before the first session.
    func retention(at date: Date, calendar: Calendar) -> AnalyticsRetention? {
        guard let firstDay = defaults.string(forKey: Self.firstSessionDayKey) else { return nil }
        let days = defaults.stringArray(forKey: Self.daysUsedKey) ?? []
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: date) ?? date
        let cutoff = AnalyticsRetention.day(monthAgo, calendar: calendar)
        return AnalyticsRetention(
            firstSessionDay: firstDay,
            totalSessions: defaults.integer(forKey: Self.sessionCountKey),
            distinctDaysUsed: days.count,
            // `yyyy-MM-dd` strings sort in date order, so this is a date comparison.
            distinctDaysUsedLastMonth: days.filter { $0 >= cutoff }.count
        )
    }
}

/// How often this install has been used, in the fields TelemetryDeck's retention charts
/// read. Counts only; the one date is the day of the first session.
struct AnalyticsRetention: Sendable, Equatable {
    /// `yyyy-MM-dd` in the person's time zone.
    let firstSessionDay: String
    let totalSessions: Int
    let distinctDaysUsed: Int
    let distinctDaysUsedLastMonth: Int

    var payload: [String: String] {
        [
            "TelemetryDeck.Acquisition.firstSessionDate": firstSessionDay,
            "TelemetryDeck.Retention.totalSessionsCount": "\(totalSessions)",
            "TelemetryDeck.Retention.distinctDaysUsed": "\(distinctDaysUsed)",
            "TelemetryDeck.Retention.distinctDaysUsedLastMonth": "\(distinctDaysUsedLastMonth)",
        ]
    }

    /// `yyyy-MM-dd` for `date` in `calendar`'s time zone, the SDK's ISO full date.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The screen as the window scene last reported it. `SceneDelegate` sets it, because
/// that is where UIKit is allowed; the sender reads it for every signal.
struct AnalyticsDisplay: Sendable, Equatable {
    /// Raw values match TelemetryDeck's SDK.
    enum Orientation: String, Sendable {
        case portrait = "Portrait"
        case landscape = "Landscape"
        case unknown = "Unknown"
    }

    let orientation: Orientation
    /// Screen size in points, in the current orientation.
    let screenWidth: Int
    let screenHeight: Int

    var payload: [String: String] {
        [
            "TelemetryDeck.Device.orientation": orientation.rawValue,
            "TelemetryDeck.Device.screenResolutionWidth": "\(screenWidth)",
            "TelemetryDeck.Device.screenResolutionHeight": "\(screenHeight)",
        ]
    }
}

/// The latest `AnalyticsDisplay` behind a lock: the scene writes it on the main actor
/// while repositories send events from their own actors.
final class AnalyticsDeviceContext: Sendable {
    private let display = OSAllocatedUnfairLock<AnalyticsDisplay?>(initialState: nil)

    func update(_ newValue: AnalyticsDisplay) {
        display.withLock { $0 = newValue }
    }

    /// Empty until the scene has reported once.
    var payload: [String: String] {
        display.withLock { $0?.payload ?? [:] }
    }
}

/// Starts analytics sessions the way TelemetryDeck's SDK does: once at launch, and again
/// when the app returns after more than `idleThreshold` in the background. `SceneDelegate`
/// reports the transitions; times are parameters so tests need no clock.
@MainActor
final class AnalyticsSessionTracker {
    static let idleThreshold: TimeInterval = 5 * 60

    private let analytics: any AnalyticsClient
    private var hasStarted = false
    private var backgroundedAt: Date?

    init(analytics: any AnalyticsClient) {
        self.analytics = analytics
    }

    func sceneWillEnterForeground(at now: Date = Date()) {
        let wasAwayLongEnough = backgroundedAt.map { now.timeIntervalSince($0) > Self.idleThreshold } ?? false
        backgroundedAt = nil
        guard !hasStarted || wasAwayLongEnough else { return }
        hasStarted = true
        analytics.send(.sessionStarted)
    }

    func sceneDidEnterBackground(at now: Date = Date()) {
        backgroundedAt = now
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
