//
//  NetworkMonitorTests.swift
//  SilverScreenTests
//
//  Reachability transitions and the reconnect counter screens use to retry, driven by
//  a scripted path source instead of NWPathMonitor.
//

import XCTest
@testable import SilverScreen

@MainActor
final class NetworkMonitorTests: XCTestCase {
    func test_init_beforeAnyUpdate_isOnlineWithNoReconnections() {
        let monitor = NetworkMonitor(source: ScriptedPathSource(values: []))

        XCTAssertTrue(monitor.isOnline)
        XCTAssertEqual(monitor.reconnections, 0)
    }

    func test_apply_dropThenReturn_countsOneReconnection() {
        let monitor = NetworkMonitor(source: ScriptedPathSource(values: []))

        monitor.apply(false)
        XCTAssertFalse(monitor.isOnline)
        XCTAssertEqual(monitor.reconnections, 0)

        monitor.apply(true)
        XCTAssertTrue(monitor.isOnline)
        XCTAssertEqual(monitor.reconnections, 1)
    }

    func test_apply_repeatedOnline_doesNotCountAsReconnection() {
        let monitor = NetworkMonitor(source: ScriptedPathSource(values: []))

        monitor.apply(true)
        monitor.apply(true)

        XCTAssertEqual(monitor.reconnections, 0)
    }

    func test_run_appliesEverySourceUpdate() async {
        let monitor = NetworkMonitor(source: ScriptedPathSource(values: [true, false, true, false]))

        await monitor.run()

        XCTAssertFalse(monitor.isOnline)
        XCTAssertEqual(monitor.reconnections, 1)
    }

    func test_retriesOnReconnect_onlyForConnectionFailures() {
        XCTAssertTrue(AppError.offline.retriesOnReconnect)
        XCTAssertTrue(AppError.timedOut.retriesOnReconnect)
        XCTAssertFalse(AppError.server(status: 500).retriesOnReconnect)
        XCTAssertFalse(AppError.decoding.retriesOnReconnect)
        XCTAssertFalse(AppError.unauthorized.retriesOnReconnect)
    }
}

/// Emits a fixed sequence of reachability values, then finishes.
private struct ScriptedPathSource: NetworkPathSource {
    let values: [Bool]

    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}
