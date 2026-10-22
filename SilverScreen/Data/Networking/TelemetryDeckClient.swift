//
//  TelemetryDeckClient.swift
//  SilverScreen
//
//  First-party sender for TelemetryDeck's v2 ingest API
//  (https://telemetrydeck.com/docs/ingest/v2), so analytics needs no SDK.
//  Events wait a few seconds in memory and go up as one JSON array. A failed
//  upload retries with backoff; a rejected one is dropped. Nothing here throws
//  into the caller or touches the main actor. Field names match TelemetryDeck's
//  SDK so its built-in charts (sessions, retention, devices) work.
//

import CryptoKit
import Foundation
import os

/// Where the app ID comes from and where signals go.
enum TelemetryDeckConfiguration {
    /// Info.plist key, filled from `TELEMETRYDECK_APP_ID` in Secrets.xcconfig.
    static let infoKey = "TelemetryDeckAppID"
    static let ingestURL = URL(string: "https://nom.telemetrydeck.com/v2/")!

    /// The app ID, or nil when it is missing, empty, unsubstituted (`$(…)`), or not a UUID.
    /// Nil turns analytics off.
    static func resolvedAppID(infoDictionary: [String: Any]) -> String? {
        guard let raw = infoDictionary[infoKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed
    }
}

/// One element of the ingest body. Field names are TelemetryDeck's.
struct TelemetryDeckSignal: Encodable, Equatable, Sendable {
    let appID: String
    /// SHA-256 of the random install ID. TelemetryDeck salts and hashes it again on receipt.
    let clientUser: String
    /// New for each `sessionStarted`, so TelemetryDeck can count sessions.
    let sessionID: String
    let type: String
    /// True in Debug builds. TelemetryDeck keeps test signals out of production charts.
    let isTestMode: Bool
    /// Flat strings only: app, OS, and device details plus retention counts, never user content.
    let payload: [String: String]
}

/// Turns an event into a signal with this launch's fixed fields.
struct TelemetryDeckSignalFactory: Sendable {
    let appID: String
    let isTestMode: Bool
    /// App, OS, and device-model fields that stay the same for the whole launch.
    let payload: [String: String]
    let preferences: AnalyticsPreferences

    /// `context` holds fields that change during a launch (orientation, retention counts)
    /// and wins over `payload` for the same key.
    func signal(for event: AnalyticsEvent, sessionID: String, context: [String: String] = [:]) -> TelemetryDeckSignal {
        TelemetryDeckSignal(
            appID: appID,
            clientUser: Self.hashed(preferences.installID()),
            sessionID: sessionID,
            type: event.rawValue,
            isTestMode: isTestMode,
            payload: payload.merging(context) { _, latest in latest }
        )
    }

    /// Lowercase hex SHA-256, the same digest TelemetryDeck's own SDK sends.
    static func hashed(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The app, OS, and device fields every signal carries. Keys and value formats are
    /// the ones TelemetryDeck's SDK uses, so the dashboard's built-in breakdowns work.
    static func defaultPayload(
        appInfo: AppInfo,
        os: OperatingSystemVersion,
        modelIdentifier: String,
        isiOSAppOnMac: Bool
    ) -> [String: String] {
        let platform = isiOSAppOnMac ? "isiOSAppOnMac" : "iOS"
        return [
            "TelemetryDeck.AppInfo.version": appInfo.marketingVersion,
            "TelemetryDeck.AppInfo.buildNumber": appInfo.build,
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "\(appInfo.marketingVersion) (build \(appInfo.build))",
            "TelemetryDeck.Device.modelName": modelIdentifier,
            "TelemetryDeck.Device.operatingSystem": "iOS",
            "TelemetryDeck.Device.platform": platform,
            "TelemetryDeck.Device.systemVersion": "\(platform) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "TelemetryDeck.Device.systemMajorVersion": "\(os.majorVersion)",
            "TelemetryDeck.Device.systemMajorMinorVersion": "\(os.majorVersion).\(os.minorVersion)",
        ]
    }

    /// Apple's model identifier, such as `iPhone17,3` or `iPad16,3`: the same for every
    /// device of that model, so it says which hardware people use without singling anyone
    /// out. A simulator reports the model it simulates; an iPhone app on a Mac reports the Mac.
    static func modelIdentifier(environment: [String: String], isiOSAppOnMac: Bool) -> String {
        if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        return sysctlString(isiOSAppOnMac ? "hw.model" : "hw.machine") ?? "Unknown"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}

/// The current session ID behind a lock, replaced on every `sessionStarted`.
final class TelemetryDeckSession: Sendable {
    private let id = OSAllocatedUnfairLock(initialState: UUID().uuidString)

    var current: String {
        id.withLock { $0 }
    }

    func rotate() {
        id.withLock { $0 = UUID().uuidString }
    }
}

/// Holds signals briefly and uploads them in batches, one request at a time.
actor TelemetryDeckOutbox {
    /// Oldest signals are dropped past this, so a long offline stretch cannot grow memory.
    static let maxPending = 100
    /// Coalesces events that happen together (create a list and add a title) into one request.
    static let batchDelay: TimeInterval = 5
    static let maxRetryDelay: TimeInterval = 15 * 60

    /// What one upload attempt means for the batch.
    enum UploadOutcome: Equatable {
        case sent
        /// The server refused the batch (bad app ID, malformed body). Retrying cannot help.
        case rejected(status: Int)
        /// Offline, timed out, rate limited, or a 5xx. Keep the batch and try again later.
        case retryLater
    }

    private let client: any HTTPClient
    private let preferences: AnalyticsPreferences
    private let sleeper: any Sleeper
    private let logger: any AppLogging
    private var pending: [TelemetryDeckSignal] = []
    private var flushTask: Task<Void, Never>?
    private var isUploading = false
    private var consecutiveFailures = 0

    init(
        client: any HTTPClient,
        preferences: AnalyticsPreferences,
        sleeper: any Sleeper = TaskSleeper(),
        logger: any AppLogging
    ) {
        self.client = client
        self.preferences = preferences
        self.sleeper = sleeper
        self.logger = logger
    }

    var pendingCount: Int { pending.count }

    /// Queues a signal and makes sure an upload is scheduled.
    func enqueue(_ signal: TelemetryDeckSignal) {
        pending.append(signal)
        trimPending()
        scheduleFlush(after: Self.batchDelay)
    }

    /// Uploads everything pending now. Drops it instead when sharing was turned off
    /// after the events were queued.
    func flush() async {
        guard preferences.isSharingEnabled else {
            pending.removeAll()
            return
        }
        guard !isUploading, !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        isUploading = true
        let outcome = await upload(batch)
        isUploading = false

        switch outcome {
            case .sent:
                consecutiveFailures = 0
            case .rejected(let status):
                consecutiveFailures = 0
                logger.debug("TelemetryDeck rejected \(batch.count) signals with status \(status)", category: .networking)
            case .retryLater:
                pending.insert(contentsOf: batch, at: 0)
                trimPending()
                consecutiveFailures += 1
                scheduleFlush(after: Self.retryDelay(afterFailures: consecutiveFailures))
                return
        }
        // Events queued while this upload was in flight still need a request.
        if !pending.isEmpty {
            scheduleFlush(after: Self.batchDelay)
        }
    }

    /// Waits for the upload `enqueue` scheduled. Lets tests observe it without sleeping.
    func waitForScheduledFlush() async {
        await flushTask?.value
    }

    /// 30 s, then doubling, capped at 15 minutes.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        let exponent = max(0, min(failures - 1, 10))
        return min(30 * pow(2, Double(exponent)), maxRetryDelay)
    }

    /// Matches TelemetryDeck's SDK: client errors that cannot succeed later are dropped.
    static func outcome(forStatus status: Int) -> UploadOutcome {
        switch status {
            case 200...299:
                .sent
            case 400, 401, 403, 404, 413, 422:
                .rejected(status: status)
            default:
                .retryLater
        }
    }

    /// POST of the batch as a JSON array.
    static func request(for batch: [TelemetryDeckSignal]) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var request = URLRequest(url: TelemetryDeckConfiguration.ingestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(batch)
        return request
    }

    private func scheduleFlush(after delay: TimeInterval) {
        guard flushTask == nil else { return }
        flushTask = Task { [sleeper] in
            try? await sleeper.sleep(seconds: delay)
            await self.runScheduledFlush()
        }
    }

    private func runScheduledFlush() async {
        flushTask = nil
        await flush()
    }

    private func upload(_ batch: [TelemetryDeckSignal]) async -> UploadOutcome {
        let request: URLRequest
        do {
            request = try Self.request(for: batch)
        } catch {
            logger.debug("TelemetryDeck batch encode failed", category: .networking)
            return .rejected(status: 0)
        }
        do {
            let (_, response) = try await client.data(for: request)
            return Self.outcome(forStatus: response.statusCode)
        } catch {
            // Never surfaced: analytics failing must not change anything the person sees.
            logger.debug("TelemetryDeck upload failed; will retry", category: .networking)
            return .retryLater
        }
    }

    private func trimPending() {
        if pending.count > Self.maxPending {
            pending.removeFirst(pending.count - Self.maxPending)
        }
    }
}

/// The live `AnalyticsClient`. `send` checks the opt-out and builds the signals on the
/// caller's thread (cheap: a few UserDefaults reads), so session IDs and counters follow
/// call order, then hands them to the outbox on a background task.
struct TelemetryDeckClient: AnalyticsClient {
    let factory: TelemetryDeckSignalFactory
    let outbox: TelemetryDeckOutbox
    let device: AnalyticsDeviceContext
    let session: TelemetryDeckSession
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        factory: TelemetryDeckSignalFactory,
        outbox: TelemetryDeckOutbox,
        device: AnalyticsDeviceContext = AnalyticsDeviceContext(),
        session: TelemetryDeckSession = TelemetryDeckSession(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.factory = factory
        self.outbox = outbox
        self.device = device
        self.session = session
        self.calendar = calendar
        self.now = now
    }

    func send(_ event: AnalyticsEvent) {
        let signals = signals(for: event)
        guard !signals.isEmpty else { return }
        Task { [outbox] in
            for signal in signals {
                await outbox.enqueue(signal)
            }
        }
    }

    /// `send`, awaitable so tests can check the outbox afterwards.
    func record(_ event: AnalyticsEvent) async {
        for signal in signals(for: event) {
            await outbox.enqueue(signal)
        }
    }

    /// The signals one event becomes. `sessionStarted` starts a new session ID and counts
    /// the session; the first one also sends `newInstallDetected`. Empty when opted out.
    func signals(for event: AnalyticsEvent) -> [TelemetryDeckSignal] {
        let preferences = factory.preferences
        guard preferences.isSharingEnabled else { return [] }
        let date = now()
        var events = [event]
        if event == .sessionStarted {
            session.rotate()
            if preferences.recordSessionStart(at: date, calendar: calendar).isNewInstall {
                events.insert(.newInstallDetected, at: 0)
            }
        }
        var context = device.payload
        if let retention = preferences.retention(at: date, calendar: calendar) {
            context.merge(retention.payload) { _, latest in latest }
        }
        let sessionID = session.current
        return events.map { factory.signal(for: $0, sessionID: sessionID, context: context) }
    }

    /// The composition root's analytics. No usable app ID means `DisabledAnalytics`.
    /// Debug builds send in TelemetryDeck's test mode.
    static func live(
        infoDictionary: [String: Any],
        client: any HTTPClient,
        preferences: AnalyticsPreferences,
        appInfo: AppInfo,
        device: AnalyticsDeviceContext,
        logger: any AppLogging
    ) -> any AnalyticsClient {
        guard let appID = TelemetryDeckConfiguration.resolvedAppID(infoDictionary: infoDictionary) else {
            return DisabledAnalytics()
        }
        #if DEBUG
        let isTestMode = true
        #else
        let isTestMode = false
        #endif
        let process = ProcessInfo.processInfo
        let factory = TelemetryDeckSignalFactory(
            appID: appID,
            isTestMode: isTestMode,
            payload: TelemetryDeckSignalFactory.defaultPayload(
                appInfo: appInfo,
                os: process.operatingSystemVersion,
                modelIdentifier: TelemetryDeckSignalFactory.modelIdentifier(
                    environment: process.environment,
                    isiOSAppOnMac: process.isiOSAppOnMac
                ),
                isiOSAppOnMac: process.isiOSAppOnMac
            ),
            preferences: preferences
        )
        let outbox = TelemetryDeckOutbox(client: client, preferences: preferences, logger: logger)
        return TelemetryDeckClient(factory: factory, outbox: outbox, device: device)
    }
}
