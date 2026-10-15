//
//  AppInfoTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class AppInfoTests: XCTestCase {
    func test_from_withVersionAndBuild_formatsLabelLikeTestFlight() {
        let info = AppInfo.from(infoDictionary: [
            "CFBundleShortVersionString": "0.1.1",
            "CFBundleVersion": "8",
        ])

        XCTAssertEqual(info.versionLabel, "0.1.1 (8)")
    }

    func test_from_withMissingOrBlankKeys_showsQuestionMarks() {
        let info = AppInfo.from(infoDictionary: ["CFBundleVersion": "  "])

        XCTAssertEqual(info, AppInfo(marketingVersion: "?", build: "?"))
    }

    func test_appLinks_privacyAndSupport_areHTTPS() {
        XCTAssertEqual(AppLinks.privacyPolicy.scheme, "https")
        XCTAssertEqual(AppLinks.support.scheme, "https")
    }
}
