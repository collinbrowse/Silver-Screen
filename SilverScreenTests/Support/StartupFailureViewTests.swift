//
//  StartupFailureViewTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class StartupFailureViewTests: XCTestCase {

    func test_message_forAppError_usesItsTitleAndMessage() {
        let error = AppError.missingAccessToken
        XCTAssertEqual(
            StartupFailureView.message(for: error),
            "\(error.title)\n\n\(error.message)"
        )
    }

    func test_message_forOtherErrors_isGeneric() {
        XCTAssertEqual(
            StartupFailureView.message(for: CocoaError(.fileReadNoPermission)),
            "The app could not start."
        )
    }

    func test_errorCode_keepsDomainAndCodeButNotThePath() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [NSFilePathErrorKey: "/Users/someone/Library/Application Support/SilverScreen"]
        )

        let code = StartupFailureView.errorCode(error)

        XCTAssertEqual(code, "NSCocoaErrorDomain 260")
        XCTAssertFalse(code.contains("someone"))
    }
}
