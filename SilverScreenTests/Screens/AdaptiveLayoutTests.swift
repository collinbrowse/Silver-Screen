//
//  AdaptiveLayoutTests.swift
//  SilverScreenTests
//
//  Widths below are what the list or screen is given, in points: iPhone 17e portrait
//  (402), iPhone Duo outer (466) and inner (669) screens, iPad mini portrait (744),
//  iPad Pro 11" portrait (834) and landscape (1194), and iPad Pro 13" landscape (1376).
//

import XCTest
@testable import SilverScreen

final class AdaptiveLayoutTests: XCTestCase {
    // MARK: - Catalog columns

    func test_catalogColumns_iPhonePortrait_isOne() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 402, isAccessibilitySize: false), 1)
    }

    func test_catalogColumns_iPhoneDuoOuterScreen_isOne() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 466, isAccessibilitySize: false), 1)
    }

    func test_catalogColumns_iPhoneDuoInnerScreen_isTwo() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 669, isAccessibilitySize: false), 2)
    }

    func test_catalogColumns_iPadPortrait_isTwo() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 834, isAccessibilitySize: false), 2)
    }

    func test_catalogColumns_iPadLandscape_isThree() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 1194, isAccessibilitySize: false), 3)
    }

    func test_catalogColumns_largeIPadLandscape_capsAtThree() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 1376, isAccessibilitySize: false), 3)
    }

    func test_catalogColumns_exactlyTwoMinimumColumns_isTwo() {
        let width = CatalogGridMetrics.minimumColumnWidth * 2 + CatalogGridMetrics.columnSpacing
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: width, isAccessibilitySize: false), 2)
    }

    func test_catalogColumns_justUnderTwoMinimumColumns_isOne() {
        let width = CatalogGridMetrics.minimumColumnWidth * 2 + CatalogGridMetrics.columnSpacing - 1
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: width, isAccessibilitySize: false), 1)
    }

    func test_catalogColumns_accessibilityTextOnWideScreen_isOne() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 1194, isAccessibilitySize: true), 1)
    }

    func test_catalogColumns_unmeasuredWidth_isOne() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 0, isAccessibilitySize: false), 1)
    }

    // MARK: - Shelf columns

    func test_shelfColumns_iPhonePortrait_keepsTwo() {
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 402), 2)
    }

    func test_shelfColumns_narrowPhone_neverDropsBelowTwo() {
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 320), 2)
    }

    func test_shelfColumns_iPhoneDuoInnerScreen_isThree() {
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 669), 3)
    }

    func test_shelfColumns_iPadPortrait_isFour() {
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 834), 4)
    }

    func test_shelfColumns_iPadLandscape_capsAtSix() {
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 1376), 6)
    }

    func test_shelfColumns_unmeasuredWidth_isTwo() {
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 0), 2)
    }

    // MARK: - Grid rows

    func test_rows_oneColumn_yieldsOneRowPerItem() {
        let rows = CatalogGrid.rows([1, 2, 3], columns: 1, id: \.self)

        XCTAssertEqual(rows.map(\.items), [[1], [2], [3]])
    }

    func test_rows_threeColumns_fillsInReadingOrderWithShortLastRow() {
        let rows = CatalogGrid.rows([1, 2, 3, 4, 5, 6, 7], columns: 3, id: \.self)

        XCTAssertEqual(rows.map(\.items), [[1, 2, 3], [4, 5, 6], [7]])
    }

    func test_rows_idIsFirstItemID() {
        let rows = CatalogGrid.rows(["a", "b", "c", "d"], columns: 2, id: \.self)

        XCTAssertEqual(rows.map(\.id), ["a", "c"])
    }

    func test_rows_marksOnlyFirstAndLastRows() {
        let rows = CatalogGrid.rows([1, 2, 3, 4, 5], columns: 2, id: \.self)

        XCTAssertEqual(rows.map(\.isFirst), [true, false, false])
        XCTAssertEqual(rows.map(\.isLast), [false, false, true])
    }

    func test_rows_singleRow_isBothFirstAndLast() {
        let rows = CatalogGrid.rows([1, 2], columns: 3, id: \.self)

        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isFirst)
        XCTAssertTrue(rows[0].isLast)
    }

    func test_rows_emptyItems_yieldsNoRows() {
        let rows = CatalogGrid.rows([Int](), columns: 2, id: \.self)

        XCTAssertTrue(rows.isEmpty)
    }

    func test_rows_zeroColumns_treatedAsOne() {
        let rows = CatalogGrid.rows([1, 2], columns: 0, id: \.self)

        XCTAssertEqual(rows.map(\.items), [[1], [2]])
    }
}
