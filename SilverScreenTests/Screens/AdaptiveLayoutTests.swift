//
//  AdaptiveLayoutTests.swift
//  SilverScreenTests
//
//  Widths below are what the list or screen is given, in points: iPhone 17e portrait
//  (402), iPhone Duo outer (466) and inner (669) screens, iPad mini portrait (744),
//  iPad Pro 11" portrait (834) and landscape (1194), and iPad Pro 13" landscape (1376).
//  The Duo's inner screen in landscape is about 866 pt once its side toolbar is excluded.
//

import SwiftUI
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

    // MARK: - Detail pages

    func test_detailTwoColumns_iPhonePortrait_isFalse() {
        XCTAssertFalse(DetailLayoutMetrics.usesTwoColumns(forWidth: 402, isAccessibilitySize: false))
    }

    func test_detailTwoColumns_iPhoneDuoInnerPortrait_isFalse() {
        XCTAssertFalse(DetailLayoutMetrics.usesTwoColumns(forWidth: 669, isAccessibilitySize: false))
    }

    func test_detailTwoColumns_iPhoneDuoInnerLandscape_isTrue() {
        XCTAssertTrue(DetailLayoutMetrics.usesTwoColumns(forWidth: 866, isAccessibilitySize: false))
    }

    func test_detailTwoColumns_iPadPortrait_isTrue() {
        XCTAssertTrue(DetailLayoutMetrics.usesTwoColumns(forWidth: 834, isAccessibilitySize: false))
    }

    func test_detailTwoColumns_accessibilityText_isFalse() {
        XCTAssertFalse(DetailLayoutMetrics.usesTwoColumns(forWidth: 1194, isAccessibilitySize: true))
    }

    func test_detailContentWidth_oneColumn_capsAtReadableWidth() {
        XCTAssertEqual(DetailLayoutMetrics.contentWidth(forWidth: 740, twoColumns: false), ReadableWidth.maximum)
    }

    func test_detailContentWidth_twoColumns_fillsWidthUpToCap() {
        XCTAssertEqual(DetailLayoutMetrics.contentWidth(forWidth: 866, twoColumns: true), 866)
        XCTAssertEqual(DetailLayoutMetrics.contentWidth(forWidth: 1376, twoColumns: true), 1180)
    }

    func test_detailContentWidth_unmeasured_isReadableWidth() {
        XCTAssertEqual(DetailLayoutMetrics.contentWidth(forWidth: 0, twoColumns: false), ReadableWidth.maximum)
    }

    func test_detailSecondaryWidth_iPhoneDuoInnerLandscape_takesShareOfPage() {
        // (866 - 32 - 24) * 0.42 = 340.2
        XCTAssertEqual(DetailLayoutMetrics.secondaryWidth(forContentWidth: 866), 340.2, accuracy: 0.01)
    }

    func test_detailSecondaryWidth_widePage_capsAtMaximum() {
        XCTAssertEqual(DetailLayoutMetrics.secondaryWidth(forContentWidth: 1180), 360)
    }

    func test_detailColumnWidths_splitsRowAfterSpacing() {
        let columns = DetailLayoutMetrics.columnWidths(totalWidth: 834, secondaryWidth: 300, spacing: 24)

        XCTAssertEqual(columns.primary, 510)
        XCTAssertEqual(columns.secondary, 300)
    }

    func test_detailColumnWidths_narrowRow_neverGoesNegative() {
        let columns = DetailLayoutMetrics.columnWidths(totalWidth: 100, secondaryWidth: 300, spacing: 24)

        XCTAssertEqual(columns.primary, 0)
        XCTAssertEqual(columns.secondary, 76)
    }

    func test_detailHeroAspectRatio_widensOnTwoColumns() {
        XCTAssertEqual(DetailLayoutMetrics.heroAspectRatio(twoColumns: false), 16.0 / 9.0)
        XCTAssertEqual(DetailLayoutMetrics.heroAspectRatio(twoColumns: true), 21.0 / 9.0)
    }

    // MARK: - Carousels

    func test_carouselPreview_iPhonePortrait_keepsFive() {
        XCTAssertEqual(CarouselMetrics.previewCount(forWidth: 402, cardWidth: 140), 5)
    }

    func test_carouselPreview_iPhoneDuoInnerLandscape_isTwiceVisibleCards() {
        // (866 - 32 + 12) / (140 + 12) = 5 whole cards visible.
        XCTAssertEqual(CarouselMetrics.visibleCardCount(forWidth: 866, cardWidth: 140), 5)
        XCTAssertEqual(CarouselMetrics.previewCount(forWidth: 866, cardWidth: 140), 10)
    }

    func test_carouselPreview_wideIPad_isTwiceVisibleCards() {
        // (1180 - 32 + 12) / 152 = 7 whole cards visible.
        XCTAssertEqual(CarouselMetrics.previewCount(forWidth: 1180, cardWidth: 140), 14)
    }

    func test_carouselViewAll_phone_keepsTenItemThreshold() {
        XCTAssertFalse(CarouselMetrics.showsViewAll(totalCount: 10, previewCount: 5))
        XCTAssertTrue(CarouselMetrics.showsViewAll(totalCount: 11, previewCount: 5))
    }

    func test_carouselViewAll_widePage_onlyBeyondPreview() {
        XCTAssertFalse(CarouselMetrics.showsViewAll(totalCount: 14, previewCount: 14))
        XCTAssertTrue(CarouselMetrics.showsViewAll(totalCount: 15, previewCount: 14))
    }

    // MARK: - Fold

    /// The Duo's inner screen opened sideways, as the 27.1 simulator reports it: a
    /// 40 pt crease at x 455.5 with 20 pt margins each side.
    private let duoCrease = FoldDivision(
        frame: CGRect(x: 455.5, y: 0, width: 40, height: 669),
        leadingMargin: 20,
        trailingMargin: 20
    )

    func test_foldSplit_duoInnerSideways_splitsAtCreaseWithMargins() throws {
        let split = try XCTUnwrap(
            FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 867, height: 669), divisions: [duoCrease])
        )

        XCTAssertEqual(split.leading, CGRect(x: 0, y: 0, width: 435.5, height: 669))
        XCTAssertEqual(split.gutter, CGRect(x: 435.5, y: 0, width: 80, height: 669))
        XCTAssertEqual(split.trailing, CGRect(x: 515.5, y: 0, width: 351.5, height: 669))
    }

    func test_foldSplit_noDivisions_isNil() {
        XCTAssertNil(FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 867, height: 669), divisions: []))
    }

    func test_foldSplit_horizontalCrease_isNil() {
        let upright = FoldDivision(frame: CGRect(x: 0, y: 455.5, width: 669, height: 40))

        XCTAssertNil(FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 669, height: 951), divisions: [upright]))
    }

    func test_foldSplit_creaseOutsideView_isNil() {
        // A view in the trailing pane only: the crease is left of it in its coordinates.
        let crease = FoldDivision(frame: CGRect(x: -100, y: 0, width: 40, height: 669))

        XCTAssertNil(FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 350, height: 669), divisions: [crease]))
    }

    func test_foldSplit_creaseNearEdge_isNil() {
        let crease = FoldDivision(frame: CGRect(x: 60, y: 0, width: 40, height: 669))

        XCTAssertNil(FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 867, height: 669), divisions: [crease]))
    }

    func test_foldSplit_rowShorterThanCrease_stillSplits() throws {
        // A list row 120 pt tall in screen space reports the crease spanning past it.
        let crease = FoldDivision(frame: CGRect(x: 439.5, y: -300, width: 40, height: 669))
        let split = try XCTUnwrap(
            FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 843, height: 120), divisions: [crease])
        )

        XCTAssertEqual(split.leading.width, 439.5)
        XCTAssertEqual(split.trailing.minX, 479.5)
        XCTAssertEqual(split.leading.height, 120)
    }

    func test_foldColumnsPerPane_usesNarrowerPane() throws {
        let split = try XCTUnwrap(
            FoldLayout.split(bounds: CGRect(x: 0, y: 0, width: 835, height: 669), divisions: [duoCrease])
        )

        // Trailing pane 319.5: (319.5 + 12) / 172 = 1.9, so one card per pane.
        XCTAssertEqual(FoldLayout.columnsPerPane(split: split, minimumCardWidth: 160, spacing: 12), 1)
    }

    func test_foldDistribute_keepsReadingOrderRowByRow() {
        let panes = FoldLayout.distribute(Array(1...7), perPane: 2)

        XCTAssertEqual(panes.leading, [1, 2, 5, 6])
        XCTAssertEqual(panes.trailing, [3, 4, 7])
    }

    // MARK: - Fold transitions

    private var bentSplit: FoldSplit {
        FoldSplit(
            leading: CGRect(x: 0, y: 0, width: 435.5, height: 669),
            gutter: CGRect(x: 435.5, y: 0, width: 80, height: 669),
            trailing: CGRect(x: 515.5, y: 0, width: 351.5, height: 669)
        )
    }

    func test_foldTransition_firstReading_doesNotAnimate() {
        XCTAssertNil(FoldTransition.animation(previous: nil, next: bentSplit, reduceMotion: false))
    }

    func test_foldTransition_hingeBends_animates() {
        let previous: FoldSplit?? = .some(nil)

        XCTAssertEqual(
            FoldTransition.animation(previous: previous, next: bentSplit, reduceMotion: false),
            FoldTransition.animation
        )
    }

    func test_foldTransition_hingeFlattens_animates() {
        let previous: FoldSplit?? = .some(bentSplit)

        XCTAssertEqual(
            FoldTransition.animation(previous: previous, next: nil, reduceMotion: false),
            FoldTransition.animation
        )
    }

    func test_foldTransition_splitOnlyMoves_leftToSystem() {
        let previous: FoldSplit?? = .some(bentSplit)
        let moved = FoldSplit(
            leading: CGRect(x: 0, y: 0, width: 419.5, height: 669),
            gutter: CGRect(x: 419.5, y: 0, width: 80, height: 669),
            trailing: CGRect(x: 499.5, y: 0, width: 335.5, height: 669)
        )

        XCTAssertNil(FoldTransition.animation(previous: previous, next: moved, reduceMotion: false))
    }

    func test_foldTransition_noFoldEitherWay_doesNotAnimate() {
        let previous: FoldSplit?? = .some(nil)

        XCTAssertNil(FoldTransition.animation(previous: previous, next: nil, reduceMotion: false))
    }

    func test_foldTransition_reduceMotion_crossFades() {
        let previous: FoldSplit?? = .some(nil)

        XCTAssertEqual(
            FoldTransition.animation(previous: previous, next: bentSplit, reduceMotion: true),
            FoldTransition.reducedMotionAnimation
        )
    }

    // MARK: - Hinge page title alignment

    func test_titleTopOffset_posterOverBackdrop_matchesTitleInset() {
        XCTAssertEqual(DetailHeroPart.titleTopOffset(posterPath: "/p.jpg", hasImages: true), 12)
    }

    func test_titleTopOffset_noPosterWithBackdrop_matchesTitleInset() {
        XCTAssertEqual(DetailHeroPart.titleTopOffset(posterPath: nil, hasImages: true), 12)
    }

    func test_titleTopOffset_blankPosterPath_countsAsNoPoster() {
        XCTAssertEqual(DetailHeroPart.titleTopOffset(posterPath: "  ", hasImages: false), 0)
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
