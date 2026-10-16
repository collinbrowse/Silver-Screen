//
//  SettingsAssetsTests.swift
//  SilverScreenTests
//
//  The TMDB logo Settings shows for attribution ships in the app bundle and
//  resolves for both light and dark appearance.
//

import UIKit
import XCTest
@testable import SilverScreen

final class SettingsAssetsTests: XCTestCase {
    func test_tmdbLogo_inLightAppearance_loadsAsWideImage() throws {
        let logo = try XCTUnwrap(tmdbLogo(style: .light))

        XCTAssertGreaterThan(logo.size.width, logo.size.height * 4)
    }

    func test_tmdbLogo_inDarkAppearance_loads() {
        XCTAssertNotNil(tmdbLogo(style: .dark))
    }

    private func tmdbLogo(style: UIUserInterfaceStyle) -> UIImage? {
        UIImage(
            named: "TMDBLogo",
            in: Bundle(for: AppDelegate.self),
            compatibleWith: UITraitCollection(userInterfaceStyle: style)
        )
    }
}
