//
//  TelemetryDeckClientTests.swift
//  SilverScreenTests
//
//  The TelemetryDeck sender: app ID resolution, the v2 ingest body, the
//  anonymous identifier, opt-out, and how uploads batch, retry, and drop.
//

import XCTest
@testable import SilverScreen

final class TelemetryDeckClientTests: XCTestCase {
    private let appID = "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE"

    // MARK: - Configuration

    func test_resolvedAppID_whenUUIDWithWhitespace_returnsTrimmedID() {
        let info: [String: Any] = ["TelemetryDeckAppID": "  \(appID)\n"]

        XCTAssertEqual(TelemetryDeckConfiguration.resolvedAppID(infoDictionary: info), appID)
    }

    func test_resolvedAppID_whenMissingEmptyUnsubstitutedOrMalformed_returnsNil() {
        let values: [Any?] = [nil, "", "   ", "$(TELEMETRYDECK_APP_ID)", "not-an-app-id", 42]

        for value in values {
            var info: [String: Any] = [:]
            info["TelemetryDeckAppID"] = value
            XCTAssertNil(TelemetryDeckConfiguration.resolvedAppID(infoDictionary: info), "\(String(describing: value))")
        }
    }

    func test_live_withoutAppID_isDisabled() {
        let client = TelemetryDeckClient.live(
            infoDictionary: ["TelemetryDeckAppID": ""],
            client: FakeHTTPClient(stub: .success(Data())),
            preferences: AnalyticsPreferences(suiteName: makeTestSuite()),
            appInfo: AppInfo(marketingVersion: "1.0", build: "1"),
            device: AnalyticsDeviceContext(),
            logger: SilentLogger()
        )

        XCTAssertTrue(client is DisabledAnalytics)
    }

    func test_live_withAppID_sendsToTelemetryDeckInTestMode() throws {
        let client = TelemetryDeckClient.live(
            infoDictionary: ["TelemetryDeckAppID": appID],
            client: FakeHTTPClient(stub: .success(Data())),
            preferences: AnalyticsPreferences(suiteName: makeTestSuite()),
            appInfo: AppInfo(marketingVersion: "1.0", build: "1"),
            device: AnalyticsDeviceContext(),
            logger: SilentLogger()
        )

        let live = try XCTUnwrap(client as? TelemetryDeckClient)
        XCTAssertEqual(live.factory.appID, appID)
        // Tests run a Debug build, which must never count as production use.
        XCTAssertTrue(live.factory.isTestMode)
    }

    // MARK: - Payload

    func test_request_postsJSONArrayToIngestV2() throws {
        let signal = makeFactory(suite: makeTestSuite()).signal(for: .listCreated, sessionID: "SESSION")

        let request = try TelemetryDeckOutbox.request(for: [signal, signal])

        XCTAssertEqual(request.url?.absoluteString, "https://nom.telemetrydeck.com/v2/")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        let body = try XCTUnwrap(request.httpBody)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(array.count, 2)
    }

    func test_request_encodesEveryIngestField() throws {
        let suite = makeTestSuite()
        let factory = makeFactory(suite: suite)
        let signal = factory.signal(for: .titleAddedToWatchlist, sessionID: "SESSION")

        let request = try TelemetryDeckOutbox.request(for: [signal])

        let body = try XCTUnwrap(request.httpBody)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let object = try XCTUnwrap(array.first)
        XCTAssertEqual(Set(object.keys), ["appID", "clientUser", "sessionID", "type", "isTestMode", "payload"])
        XCTAssertEqual(object["appID"] as? String, appID)
        XCTAssertEqual(object["type"] as? String, "Library.titleAddedToWatchlist")
        XCTAssertEqual(object["sessionID"] as? String, "SESSION")
        XCTAssertEqual(object["isTestMode"] as? Bool, true)
        let payload = try XCTUnwrap(object["payload"] as? [String: String])
        XCTAssertEqual(payload["TelemetryDeck.AppInfo.version"], "1.2.0")
        XCTAssertEqual(payload["TelemetryDeck.AppInfo.buildNumber"], "14")
    }

    func test_signal_clientUserIsHashOfInstallID_neverTheIDItself() {
        let suite = makeTestSuite()
        let preferences = AnalyticsPreferences(suiteName: suite)
        let installID = preferences.installID()

        let signal = makeFactory(suite: suite).signal(for: .firstRating, sessionID: "SESSION")

        XCTAssertEqual(signal.clientUser, TelemetryDeckSignalFactory.hashed(installID))
        XCTAssertEqual(signal.clientUser.count, 64)
        XCTAssertFalse(signal.clientUser.contains(installID))
    }

    func test_hashed_isLowercaseHexSHA256() {
        XCTAssertEqual(
            TelemetryDeckSignalFactory.hashed("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func test_defaultPayload_carriesAppOSAndModelOnly() {
        let payload = TelemetryDeckSignalFactory.defaultPayload(
            appInfo: AppInfo(marketingVersion: "1.2.0", build: "14"),
            os: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2),
            modelIdentifier: "iPhone17,3",
            isiOSAppOnMac: false
        )

        XCTAssertEqual(payload, [
            "TelemetryDeck.AppInfo.version": "1.2.0",
            "TelemetryDeck.AppInfo.buildNumber": "14",
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "1.2.0 (build 14)",
            "TelemetryDeck.Device.modelName": "iPhone17,3",
            "TelemetryDeck.Device.operatingSystem": "iOS",
            "TelemetryDeck.Device.platform": "iOS",
            "TelemetryDeck.Device.systemVersion": "iOS 26.1.2",
            "TelemetryDeck.Device.systemMajorVersion": "26",
            "TelemetryDeck.Device.systemMajorMinorVersion": "26.1",
        ])
    }

    func test_defaultPayload_onMac_reportsSDKPlatformName() {
        let payload = TelemetryDeckSignalFactory.defaultPayload(
            appInfo: AppInfo(marketingVersion: "1.2.0", build: "14"),
            os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            modelIdentifier: "Mac16,10",
            isiOSAppOnMac: true
        )

        XCTAssertEqual(payload["TelemetryDeck.Device.platform"], "isiOSAppOnMac")
        XCTAssertEqual(payload["TelemetryDeck.Device.systemVersion"], "isiOSAppOnMac 26.0.0")
    }

    func test_modelIdentifier_onSimulator_reportsSimulatedModel() {
        let model = TelemetryDeckSignalFactory.modelIdentifier(
            environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone18,5"],
            isiOSAppOnMac: false
        )

        XCTAssertEqual(model, "iPhone18,5")
    }

    func test_modelIdentifier_withoutSimulator_readsHardwareModel() {
        let model = TelemetryDeckSignalFactory.modelIdentifier(environment: [:], isiOSAppOnMac: false)

        // The test host is a simulator on a Mac, so hw.machine is the host CPU; it must still be a real value.
        XCTAssertFalse(model.isEmpty)
        XCTAssertNotEqual(model, "Unknown")
    }

    func test_signal_contextWinsOverLaunchPayload() {
        let signal = makeFactory(suite: makeTestSuite()).signal(
            for: .listCreated,
            sessionID: "SESSION",
            context: ["TelemetryDeck.AppInfo.version": "override", "TelemetryDeck.Device.orientation": "Landscape"]
        )

        XCTAssertEqual(signal.payload["TelemetryDeck.AppInfo.version"], "override")
        XCTAssertEqual(signal.payload["TelemetryDeck.Device.orientation"], "Landscape")
        XCTAssertEqual(signal.payload["TelemetryDeck.AppInfo.buildNumber"], "14")
    }

    // MARK: - Opt-out

    func test_record_whenSharingOn_queuesSignal() async {
        let suite = makeTestSuite()
        let outbox = makeOutbox(client: FakeHTTPClient(stub: .success(Data())), suite: suite, sleeper: GateSleeper())
        let client = TelemetryDeckClient(factory: makeFactory(suite: suite), outbox: outbox)

        await client.record(.listCreated)

        let pending = await outbox.pendingCount
        XCTAssertEqual(pending, 1)
    }

    func test_record_whenOptedOut_queuesNothing() async {
        let suite = makeTestSuite()
        AnalyticsPreferences(suiteName: suite).setSharingEnabled(false)
        let outbox = makeOutbox(client: FakeHTTPClient(stub: .success(Data())), suite: suite, sleeper: GateSleeper())
        let client = TelemetryDeckClient(factory: makeFactory(suite: suite), outbox: outbox)

        await client.record(.listCreated)

        let pending = await outbox.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func test_flush_whenOptedOutAfterQueueing_dropsWithoutUploading() async {
        let suite = makeTestSuite()
        let http = RecordingHTTPClient(stub: .success(Data()))
        let outbox = makeOutbox(client: http, suite: suite, sleeper: GateSleeper())
        await outbox.enqueue(makeFactory(suite: suite).signal(for: .listCreated, sessionID: "SESSION"))
        AnalyticsPreferences(suiteName: suite).setSharingEnabled(false)

        await outbox.flush()

        let requests = await http.requestCount
        let pending = await outbox.pendingCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(pending, 0)
    }

    func test_setSharingEnabledFalse_forgetsInstallID() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())
        let first = preferences.installID()

        preferences.setSharingEnabled(false)
        preferences.setSharingEnabled(true)

        XCTAssertNotEqual(preferences.installID(), first)
    }

    func test_installID_isStableAndRandom() {
        let preferences = AnalyticsPreferences(suiteName: makeTestSuite())
        let other = AnalyticsPreferences(suiteName: makeTestSuite())

        XCTAssertEqual(preferences.installID(), preferences.installID())
        XCTAssertNotEqual(preferences.installID(), other.installID())
        XCTAssertNotNil(UUID(uuidString: preferences.installID()))
    }

    @MainActor
    func test_analyticsSharing_toggleWritesThrough() {
        let suite = makeTestSuite()
        let preferences = AnalyticsPreferences(suiteName: suite)
        let sharing = AnalyticsSharing(preferences: preferences)
        XCTAssertTrue(sharing.isEnabled)

        sharing.isEnabled = false

        XCTAssertFalse(preferences.isSharingEnabled)
        XCTAssertTrue(UserDefaults(suiteName: suite)?.bool(forKey: AnalyticsPreferences.optedOutKey) ?? false)
    }

    // MARK: - Batching and retry

    func test_enqueue_schedulesOneUploadForEventsTogether() async throws {
        let suite = makeTestSuite()
        let http = RecordingHTTPClient(stub: .success(Data()))
        let sleeper = GateSleeper()
        let outbox = makeOutbox(client: http, suite: suite, sleeper: sleeper)
        let factory = makeFactory(suite: suite)
        await outbox.enqueue(factory.signal(for: .listCreated, sessionID: "SESSION"))
        await outbox.enqueue(factory.signal(for: .titleAddedToWatchlist, sessionID: "SESSION"))

        await sleeper.open()
        await outbox.waitForScheduledFlush()

        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
        let body = try XCTUnwrap(requests.first?.httpBody)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(array.compactMap { $0["type"] as? String }, ["Library.listCreated", "Library.titleAddedToWatchlist"])
        let pending = await outbox.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func test_flush_whenServerErrors_keepsBatchForRetry() async {
        let pending = await pendingAfterFlush(stub: .success(Data(), status: 503))

        XCTAssertEqual(pending, 1)
    }

    func test_flush_whenOffline_keepsBatchForRetry() async {
        let pending = await pendingAfterFlush(stub: .failure(URLError(.notConnectedToInternet)))

        XCTAssertEqual(pending, 1)
    }

    func test_flush_whenRejected_dropsBatch() async {
        let pending = await pendingAfterFlush(stub: .success(Data(), status: 401))

        XCTAssertEqual(pending, 0)
    }

    func test_outcome_matchesTelemetryDeckSDK() {
        XCTAssertEqual(TelemetryDeckOutbox.outcome(forStatus: 200), .sent)
        XCTAssertEqual(TelemetryDeckOutbox.outcome(forStatus: 202), .sent)
        for status in [400, 401, 403, 404, 413, 422] {
            XCTAssertEqual(TelemetryDeckOutbox.outcome(forStatus: status), .rejected(status: status))
        }
        for status in [408, 429, 500, 503] {
            XCTAssertEqual(TelemetryDeckOutbox.outcome(forStatus: status), .retryLater)
        }
    }

    func test_retryDelay_doublesAndCaps() {
        XCTAssertEqual(TelemetryDeckOutbox.retryDelay(afterFailures: 1), 30)
        XCTAssertEqual(TelemetryDeckOutbox.retryDelay(afterFailures: 2), 60)
        XCTAssertEqual(TelemetryDeckOutbox.retryDelay(afterFailures: 3), 120)
        XCTAssertEqual(TelemetryDeckOutbox.retryDelay(afterFailures: 50), TelemetryDeckOutbox.maxRetryDelay)
    }

    func test_enqueue_pastLimit_dropsOldest() async {
        let suite = makeTestSuite()
        let outbox = makeOutbox(client: FakeHTTPClient(stub: .success(Data())), suite: suite, sleeper: GateSleeper())
        let signal = makeFactory(suite: suite).signal(for: .listCreated, sessionID: "SESSION")

        for _ in 0..<(TelemetryDeckOutbox.maxPending + 5) {
            await outbox.enqueue(signal)
        }

        let pending = await outbox.pendingCount
        XCTAssertEqual(pending, TelemetryDeckOutbox.maxPending)
    }

    // MARK: - Helpers

    private func makeFactory(suite: String) -> TelemetryDeckSignalFactory {
        TelemetryDeckSignalFactory(
            appID: appID,
            isTestMode: true,
            payload: TelemetryDeckSignalFactory.defaultPayload(
                appInfo: AppInfo(marketingVersion: "1.2.0", build: "14"),
                os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                modelIdentifier: "iPhone17,3",
                isiOSAppOnMac: false
            ),
            preferences: AnalyticsPreferences(suiteName: suite)
        )
    }

    private func makeOutbox(client: any HTTPClient, suite: String, sleeper: any Sleeper) -> TelemetryDeckOutbox {
        TelemetryDeckOutbox(
            client: client,
            preferences: AnalyticsPreferences(suiteName: suite),
            sleeper: sleeper,
            logger: SilentLogger()
        )
    }

    /// One queued signal, one explicit flush against `stub`. The gate stays shut, so a
    /// scheduled retry never runs during the test.
    private func pendingAfterFlush(stub: FakeHTTPClient.Stub) async -> Int {
        let suite = makeTestSuite()
        let outbox = makeOutbox(client: FakeHTTPClient(stub: stub), suite: suite, sleeper: GateSleeper())
        await outbox.enqueue(makeFactory(suite: suite).signal(for: .listCreated, sessionID: "SESSION"))
        await outbox.flush()
        return await outbox.pendingCount
    }
}
