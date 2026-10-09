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
}
