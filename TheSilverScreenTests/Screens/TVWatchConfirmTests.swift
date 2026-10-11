//
//  TVWatchConfirmTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

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
            "This clears 1 watched episode."
        )
        XCTAssertEqual(
            TVWatchConfirm.clearMessage(episodeCount: 12),
            "This clears 12 watched episodes."
        )
    }
}
