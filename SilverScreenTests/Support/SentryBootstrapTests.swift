//
//  SentryBootstrapTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class SentryBootstrapTests: XCTestCase {
    func test_sendFeedback_whenNotStarted_returnsFalse() throws {
        try XCTSkipIf(SentryBootstrap.isStarted, "This host started Sentry with a real DSN.")
        XCTAssertFalse(SentryBootstrap.sendFeedback(message: "Hi", email: nil))
    }

    func testReleaseNameMatchesTestFlightShape() {
        XCTAssertEqual(SentryBootstrap.releaseName(marketing: "0.1.1", build: "5"), "0.1.1+5")
    }

    func testResolvedDSNIgnoresEmptyAndUnsubstituted() {
        XCTAssertNil(SentryBootstrap.resolvedDSN(infoDictionary: ["SentryDSN": ""]))
        XCTAssertNil(SentryBootstrap.resolvedDSN(infoDictionary: ["SentryDSN": "$(SENTRY_DSN)"]))
        XCTAssertNil(SentryBootstrap.resolvedDSN(infoDictionary: [:]))
    }

    func testResolvedDSNAcceptsTrimmedValue() {
        XCTAssertEqual(
            SentryBootstrap.resolvedDSN(
                infoDictionary: ["SentryDSN": "  https://abc123@example.ingest.sentry.io/1  "]
            ),
            "https://abc123@example.ingest.sentry.io/1"
        )
    }

    func testResolvedDSNStripsXcconfigEmptySubstitution() {
        XCTAssertEqual(
            SentryBootstrap.resolvedDSN(
                infoDictionary: [
                    "SentryDSN": "https:/$()/abc123@o1.ingest.us.sentry.io/2"
                ]
            ),
            "https://abc123@o1.ingest.us.sentry.io/2"
        )
    }

    func testResolvedDSNRejectsNonHTTPS() {
        XCTAssertNil(
            SentryBootstrap.resolvedDSN(infoDictionary: ["SentryDSN": "http://abc@host/1"])
        )
    }

    func testReleaseNameFromInfoRequiresBothNumbers() {
        XCTAssertNil(
            SentryBootstrap.releaseName(infoDictionary: ["CFBundleShortVersionString": "1.0.0"])
        )
        XCTAssertEqual(
            SentryBootstrap.releaseName(
                infoDictionary: [
                    "CFBundleShortVersionString": "0.1.1",
                    "CFBundleVersion": "5",
                ]
            ),
            "0.1.1+5"
        )
    }
}
