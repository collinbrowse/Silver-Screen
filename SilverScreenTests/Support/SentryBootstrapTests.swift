//
//  SentryBootstrapTests.swift
//  SilverScreenTests
//

import XCTest
import Sentry
@testable import SilverScreen

final class SentryBootstrapTests: XCTestCase {
    func test_sendFeedback_whenNotStarted_returnsFalse() throws {
        try XCTSkipIf(SentryBootstrap.isStarted, "This host started Sentry with a real DSN.")
        XCTAssertFalse(SentryBootstrap.sendFeedback(message: "Hi", email: nil))
    }

    func test_configure_dropsSearchQueryFromHTTPBreadcrumbs() throws {
        let options = Options()
        SentryBootstrap.configure(options, dsn: "https://abc@example.ingest.sentry.io/1", infoDictionary: [:])
        let breadcrumb = Breadcrumb(level: .info, category: "http")
        breadcrumb.data = [
            "url": "https://api.themoviedb.org/3/search/movie",
            "http.query": "query=my+secret+search&page=1",
            "http.fragment": "top",
            "status_code": 200,
        ]

        let sent = try XCTUnwrap(options.beforeBreadcrumb?(breadcrumb))

        XCTAssertNil(sent.data?["http.query"])
        XCTAssertNil(sent.data?["http.fragment"])
        XCTAssertEqual(sent.data?["url"] as? String, "https://api.themoviedb.org/3/search/movie")
    }

    func test_configure_sendsNoFailedRequestEventsAndTagsDebugRuns() {
        let options = Options()
        SentryBootstrap.configure(options, dsn: "https://abc@example.ingest.sentry.io/1", infoDictionary: [:])

        XCTAssertFalse(options.enableCaptureFailedRequests)
        XCTAssertFalse(options.sendDefaultPii)
        XCTAssertNotNil(options.beforeSendSpan)
        XCTAssertEqual(options.environment, "debug")
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
