//
//  AnalyticsSessionTests.swift
//  SilverScreenTests
//
//  Sessions, retention counts, and device fields: when a session starts, what
//  the first one adds, and what every signal carries afterwards.
//

import XCTest
@testable import SilverScreen

final class AnalyticsSessionTests: XCTestCase {
    private let appID = "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE"
    private let launch = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Session tracker

    @MainActor
    func test_tracker_firstForeground_startsSession() {
        let spy = SpyAnalyticsClient()
        let tracker = AnalyticsSessionTracker(analytics: spy)

        tracker.sceneWillEnterForeground(at: launch)

        XCTAssertEqual(spy.events, [.sessionStarted])
    }

    @MainActor
    func test_tracker_shortTimeAway_keepsSession() {
        let spy = SpyAnalyticsClient()
        let tracker = AnalyticsSessionTracker(analytics: spy)
        tracker.sceneWillEnterForeground(at: launch)
        tracker.sceneDidEnterBackground(at: launch)

        tracker.sceneWillEnterForeground(at: launch.addingTimeInterval(AnalyticsSessionTracker.idleThreshold))

        XCTAssertEqual(spy.events, [.sessionStarted])
    }

    @MainActor
    func test_tracker_awayPastThreshold_startsNewSession() {
        let spy = SpyAnalyticsClient()
        let tracker = AnalyticsSessionTracker(analytics: spy)
        tracker.sceneWillEnterForeground(at: launch)
        tracker.sceneDidEnterBackground(at: launch)

        tracker.sceneWillEnterForeground(at: launch.addingTimeInterval(AnalyticsSessionTracker.idleThreshold + 1))

        XCTAssertEqual(spy.events, [.sessionStarted, .sessionStarted])
    }

    @MainActor
    func test_tracker_foregroundWithoutBackground_keepsSession() {
        let spy = SpyAnalyticsClient()
        let tracker = AnalyticsSessionTracker(analytics: spy)
        tracker.sceneWillEnterForeground(at: launch)

        tracker.sceneWillEnterForeground(at: launch.addingTimeInterval(3600))

        XCTAssertEqual(spy.events, [.sessionStarted])
    }

    // MARK: - Retention counts

    func test_recordSessionStart_first_isNewInstallWithOneOfEverything() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())

        let result = preferences.recordSessionStart(at: launch, calendar: utc)

        XCTAssertTrue(result.isNewInstall)
        XCTAssertEqual(result.retention, AnalyticsRetention(
            firstSessionDay: "2026-10-16",
            totalSessions: 1,
            distinctDaysUsed: 1,
            distinctDaysUsedLastMonth: 1
        ))
    }

    func test_recordSessionStart_sameDay_countsSessionNotDay() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())
        _ = preferences.recordSessionStart(at: launch, calendar: utc)

        let result = preferences.recordSessionStart(at: launch.addingTimeInterval(3600), calendar: utc)

        XCTAssertFalse(result.isNewInstall)
        XCTAssertEqual(result.retention.totalSessions, 2)
        XCTAssertEqual(result.retention.distinctDaysUsed, 1)
    }

    func test_recordSessionStart_laterDays_countsDaysAndLastMonth() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())
        _ = preferences.recordSessionStart(at: launch, calendar: utc)
        _ = preferences.recordSessionStart(at: day(1), calendar: utc)

        let result = preferences.recordSessionStart(at: day(40), calendar: utc)

        XCTAssertEqual(result.retention.firstSessionDay, "2026-10-16")
        XCTAssertEqual(result.retention.totalSessions, 3)
        XCTAssertEqual(result.retention.distinctDaysUsed, 3)
        // Only day 40 is within 30 days of day 40.
        XCTAssertEqual(result.retention.distinctDaysUsedLastMonth, 1)
    }

    func test_retention_beforeFirstSession_isNil() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())

        XCTAssertNil(preferences.retention(at: launch, calendar: utc))
    }

    func test_optOut_forgetsRetention_soOptingBackInIsANewInstall() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())
        _ = preferences.recordSessionStart(at: launch, calendar: utc)

        preferences.setSharingEnabled(false)
        preferences.setSharingEnabled(true)

        XCTAssertNil(preferences.retention(at: launch, calendar: utc))
        XCTAssertTrue(preferences.recordSessionStart(at: day(1), calendar: utc).isNewInstall)
    }

    func test_retentionPayload_usesSDKKeys() {
        let retention = AnalyticsRetention(
            firstSessionDay: "2026-10-16",
            totalSessions: 7,
            distinctDaysUsed: 4,
            distinctDaysUsedLastMonth: 2
        )

        XCTAssertEqual(retention.payload, [
            "TelemetryDeck.Acquisition.firstSessionDate": "2026-10-16",
            "TelemetryDeck.Retention.totalSessionsCount": "7",
            "TelemetryDeck.Retention.distinctDaysUsed": "4",
            "TelemetryDeck.Retention.distinctDaysUsedLastMonth": "2",
        ])
    }

    // MARK: - Signals

    func test_firstSession_sendsNewInstallThenSessionStarted_inOneNewSession() {
        let client = makeClient(suite: makeTestSuite())
        let earlier = client.session.current

        let signals = client.signals(for: .sessionStarted)

        XCTAssertEqual(signals.map(\.type), ["TelemetryDeck.Acquisition.newInstallDetected", "TelemetryDeck.Session.started"])
        XCTAssertEqual(Set(signals.map(\.sessionID)).count, 1)
        XCTAssertNotEqual(signals.first?.sessionID, earlier)
        XCTAssertEqual(signals.first?.payload["TelemetryDeck.Retention.totalSessionsCount"], "1")
    }

    func test_laterSession_sendsOnlySessionStarted_withNewID() {
        let client = makeClient(suite: makeTestSuite())
        let first = client.signals(for: .sessionStarted)

        let second = client.signals(for: .sessionStarted)

        XCTAssertEqual(second.map(\.type), ["TelemetryDeck.Session.started"])
        XCTAssertNotEqual(second.first?.sessionID, first.first?.sessionID)
        XCTAssertEqual(second.first?.payload["TelemetryDeck.Retention.totalSessionsCount"], "2")
    }

    func test_eventAfterSession_sharesSessionAndCarriesRetentionAndDisplay() throws {
        let device = AnalyticsDeviceContext()
        let client = makeClient(suite: makeTestSuite(), device: device)
        let session = client.signals(for: .sessionStarted)
        device.update(AnalyticsDisplay(orientation: .landscape, screenWidth: 874, screenHeight: 402))

        let signal = try XCTUnwrap(client.signals(for: .listCreated).first)

        XCTAssertEqual(signal.sessionID, session.last?.sessionID)
        XCTAssertEqual(signal.payload["TelemetryDeck.Acquisition.firstSessionDate"], "2026-10-16")
        XCTAssertEqual(signal.payload["TelemetryDeck.Device.orientation"], "Landscape")
        XCTAssertEqual(signal.payload["TelemetryDeck.Device.screenResolutionWidth"], "874")
        XCTAssertEqual(signal.payload["TelemetryDeck.Device.screenResolutionHeight"], "402")
        XCTAssertEqual(signal.payload["TelemetryDeck.Device.modelName"], "iPhone17,3")
    }

    func test_beforeSceneReports_signalHasNoDisplayFields() throws {
        let client = makeClient(suite: makeTestSuite())

        let signal = try XCTUnwrap(client.signals(for: .listCreated).first)

        XCTAssertNil(signal.payload["TelemetryDeck.Device.orientation"])
        XCTAssertNil(signal.payload["TelemetryDeck.Retention.totalSessionsCount"])
    }

    func test_signals_whenOptedOut_areEmptyAndCountNothing() {
        let suite = makeTestSuite()
        let preferences = AnalyticsPreferences(suiteName: suite)
        preferences.setSharingEnabled(false)
        let client = makeClient(suite: suite)

        XCTAssertEqual(client.signals(for: .sessionStarted), [])
        XCTAssertNil(preferences.retention(at: launch, calendar: utc))
    }

    func test_displayPayload_usesSDKKeysAndValues() {
        let display = AnalyticsDisplay(orientation: .portrait, screenWidth: 402, screenHeight: 874)

        XCTAssertEqual(display.payload, [
            "TelemetryDeck.Device.orientation": "Portrait",
            "TelemetryDeck.Device.screenResolutionWidth": "402",
            "TelemetryDeck.Device.screenResolutionHeight": "874",
        ])
    }

    // MARK: - Helpers

    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: launch)!
    }

    private func makeClient(suite: String, device: AnalyticsDeviceContext = AnalyticsDeviceContext()) -> TelemetryDeckClient {
        let preferences = AnalyticsPreferences(suiteName: suite)
        let factory = TelemetryDeckSignalFactory(
            appID: appID,
            isTestMode: true,
            payload: TelemetryDeckSignalFactory.defaultPayload(
                appInfo: AppInfo(marketingVersion: "1.2.0", build: "14"),
                os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                modelIdentifier: "iPhone17,3",
                isiOSAppOnMac: false
            ),
            preferences: preferences
        )
        let outbox = TelemetryDeckOutbox(
            client: FakeHTTPClient(stub: .success(Data())),
            preferences: preferences,
            sleeper: GateSleeper(),
            logger: SilentLogger()
        )
        let launch = self.launch
        return TelemetryDeckClient(
            factory: factory,
            outbox: outbox,
            device: device,
            calendar: utc,
            now: { launch }
        )
    }
}
