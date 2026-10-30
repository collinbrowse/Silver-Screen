//
//  TVWatchConfirmTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class TVWatchConfirmTests: XCTestCase {
    func test_message_usesSingularAndPlural() {
        XCTAssertEqual(
            TVWatchConfirm.message(episodeCount: 1),
            "This marks 1 episode as watched."
        )
        XCTAssertEqual(
            TVWatchConfirm.message(episodeCount: 42),
            "This marks 42 episodes as watched."
        )
    }

    func test_clearMessage_usesSingularAndPlural() {
        XCTAssertEqual(
            TVWatchConfirm.clearMessage(episodeCount: 1),
            "This removes 1 watched episode and its ratings and reviews."
        )
        XCTAssertEqual(
            TVWatchConfirm.clearMessage(episodeCount: 12),
            "This removes 12 watched episodes and their ratings and reviews."
        )
    }
}
