//
//  AwardRowsDisplayTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class AwardRowsDisplayTests: XCTestCase {
    func test_visibleRows_whenAtOrUnderLimit_returnsAll() {
        let rows = Array(1...5)

        XCTAssertEqual(
            AwardRowsDisplay.visibleRows(from: rows, isExpanded: false),
            rows
        )
        XCTAssertEqual(
            AwardRowsDisplay.visibleRows(from: rows, isExpanded: true),
            rows
        )
    }

    func test_visibleRows_whenCollapsedPastLimit_returnsFirstFive() {
        let rows = Array(1...8)

        XCTAssertEqual(
            AwardRowsDisplay.visibleRows(from: rows, isExpanded: false),
            [1, 2, 3, 4, 5]
        )
    }

    func test_visibleRows_whenExpandedPastLimit_returnsAll() {
        let rows = Array(1...8)

        XCTAssertEqual(
            AwardRowsDisplay.visibleRows(from: rows, isExpanded: true),
            rows
        )
    }

    func test_showsToggle_onlyWhenPastLimit() {
        XCTAssertFalse(AwardRowsDisplay.showsToggle(total: 5))
        XCTAssertTrue(AwardRowsDisplay.showsToggle(total: 6))
    }

    func test_toggleTitle_flipsWithExpandedState() {
        XCTAssertEqual(AwardRowsDisplay.toggleTitle(isExpanded: false), "Show more")
        XCTAssertEqual(AwardRowsDisplay.toggleTitle(isExpanded: true), "Show less")
    }
}
