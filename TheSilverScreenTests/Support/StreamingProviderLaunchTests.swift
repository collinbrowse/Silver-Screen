//
//  StreamingProviderLaunchTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class StreamingProviderLaunchTests: XCTestCase {
    func test_destination_resolvesKnownTMDBProviderIDs() {
        let netflix = StreamingProviderLaunch.destination(for: 8)
        XCTAssertEqual(netflix?.urlScheme, "nflx")

        let max = StreamingProviderLaunch.destination(for: 1899)
        XCTAssertEqual(max?.urlScheme, "max")

        XCTAssertNil(StreamingProviderLaunch.destination(for: 999_999))
    }

    func test_targetURL_usesAppSchemeWhenInstalled() {
        let provider = StreamingProvider(id: 8, name: "Netflix", logoPath: "/n.jpg")
        let url = StreamingProviderLaunch.targetURL(for: provider, isAppInstalled: { _ in true })
        XCTAssertEqual(url?.scheme, "nflx")
    }

    func test_targetURL_usesAppStoreWhenNotInstalled() {
        let provider = StreamingProvider(id: 337, name: "Disney Plus", logoPath: "/d.jpg")
        let url = StreamingProviderLaunch.targetURL(for: provider, isAppInstalled: { _ in false })
        XCTAssertEqual(url?.absoluteString, "https://apps.apple.com/app/id1446075923")
    }

    func test_targetURL_isNilForUnknownProvider() {
        let provider = StreamingProvider(id: 12_345, name: "Unknown", logoPath: nil)
        XCTAssertNil(StreamingProviderLaunch.targetURL(for: provider, isAppInstalled: { _ in true }))
    }

    func test_accessibilityLabel_reflectsInstallState() {
        let provider = StreamingProvider(id: 15, name: "Hulu", logoPath: nil)
        XCTAssertEqual(
            StreamingProviderLaunch.accessibilityLabel(for: provider, isAppInstalled: { _ in true }),
            "Open Hulu"
        )
        XCTAssertEqual(
            StreamingProviderLaunch.accessibilityLabel(for: provider, isAppInstalled: { _ in false }),
            "Get Hulu on the App Store"
        )
    }

    func test_destination_mapsPeacockAndYouTubeTV() {
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 386)?.urlScheme, "peacock")
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 387)?.urlScheme, "peacock")
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 2528)?.urlScheme, "youtubetv")
    }

    func test_destination_amcPlusIsNotAppleTV() {
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 526)?.urlScheme, "amcplus")
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 350)?.urlScheme, "videos")
        XCTAssertNil(StreamingProviderLaunch.destination(for: 526).flatMap { dest in
            dest.urlScheme == "videos" ? dest : nil
        })
    }

    func test_destination_plutoUsesPlutoNotCriterionID() {
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 300)?.urlScheme, "plutotv")
        XCTAssertEqual(StreamingProviderLaunch.destination(for: 258)?.urlScheme, "criterionchannel")
    }
}
