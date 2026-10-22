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

    func test_catalogColumns_largerTextWidensColumns_iPhoneDuoInnerScreenIsOne() {
        // 300 pt scaled for a larger text size.
        XCTAssertEqual(
            CatalogGridMetrics.columnCount(forWidth: 669, isAccessibilitySize: false, minimumColumnWidth: 350),
            1
        )
    }

    func test_catalogColumns_folded_isOnePerPane() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 1194, isFolded: true, isAccessibilitySize: false), 2)
    }

    func test_catalogColumns_foldedAtAccessibilitySize_isStillOnePerPane() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 867, isFolded: true, isAccessibilitySize: true), 2)
    }

    func test_catalogColumns_notFolded_followsWidth() {
        XCTAssertEqual(CatalogGridMetrics.columnCount(forWidth: 1194, isFolded: false, isAccessibilitySize: false), 3)
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

    // MARK: - Detail page layout

    func test_detailPageLayout_iPhonePortrait_isStacked() {
        XCTAssertEqual(DetailPageLayout.resolve(width: 402, fold: nil, isAccessibilitySize: false), .stacked)
    }

    func test_detailPageLayout_iPhoneDuoInnerPortrait_isStacked() {
        XCTAssertEqual(DetailPageLayout.resolve(width: 669, fold: nil, isAccessibilitySize: false), .stacked)
    }

    func test_detailPageLayout_iPhoneDuoInnerLandscape_isColumns() {
        XCTAssertEqual(DetailPageLayout.resolve(width: 866, fold: nil, isAccessibilitySize: false), .columns)
    }

    func test_detailPageLayout_accessibilityTextOnIPad_isStacked() {
        XCTAssertEqual(DetailPageLayout.resolve(width: 1194, fold: nil, isAccessibilitySize: true), .stacked)
    }

    func test_detailPageLayout_largerTextRaisesBreakpoint_iPadPortraitStacks() {
        // 760 pt scaled for a larger text size.
        let layout = DetailPageLayout.resolve(
            width: 834,
            fold: nil,
            isAccessibilitySize: false,
            twoColumnMinimumWidth: 900
        )

        XCTAssertEqual(layout, .stacked)
    }

    func test_detailPageLayout_hingeBent_isPanes() {
        XCTAssertEqual(DetailPageLayout.resolve(width: 867, fold: bentSplit, isAccessibilitySize: false), .panes)
    }

    func test_detailPageLayout_hingeBentAtAccessibilitySize_isStillPanes() {
        XCTAssertEqual(DetailPageLayout.resolve(width: 867, fold: bentSplit, isAccessibilitySize: true), .panes)
    }

    func test_detailPageLayout_hingeBentBelowTwoColumnWidth_isStillPanes() {
        let fold = FoldSplit(
            leading: CGRect(x: 0, y: 0, width: 320, height: 669),
            gutter: CGRect(x: 320, y: 0, width: 60, height: 669),
            trailing: CGRect(x: 380, y: 0, width: 320, height: 669)
        )

        XCTAssertEqual(DetailPageLayout.resolve(width: 700, fold: fold, isAccessibilitySize: false), .panes)
    }

    func test_detailPageLayout_foldPaneNarrowerThanAColumn_fallsBackToWidth() {
        let fold = FoldSplit(
            leading: CGRect(x: 0, y: 0, width: 627, height: 669),
            gutter: CGRect(x: 627, y: 0, width: 40, height: 669),
            trailing: CGRect(x: 667, y: 0, width: 200, height: 669)
        )

        XCTAssertEqual(DetailPageLayout.resolve(width: 867, fold: fold, isAccessibilitySize: false), .columns)
    }

    func test_detailPageLayout_panes_useWideHeroAndCap() {
        XCTAssertEqual(DetailPageLayout.panes.heroAspectRatio, DetailLayoutMetrics.wideHeroAspectRatio)
        XCTAssertEqual(DetailPageLayout.panes.columnCap, DetailLayoutMetrics.maximumContentWidth)
        XCTAssertEqual(DetailPageLayout.stacked.columnCap, ReadableWidth.maximum)
    }

    func test_detailGridColumns_belowTwoColumnPage_isTwo() {
        XCTAssertEqual(DetailPageLayout.columns.gridColumns(in: .below), 2)
    }

    func test_detailGridColumns_inAColumnOrOnAPhone_isOne() {
        XCTAssertEqual(DetailPageLayout.columns.gridColumns(in: .main), 1)
        XCTAssertEqual(DetailPageLayout.panes.gridColumns(in: .main), 1)
        XCTAssertEqual(DetailPageLayout.stacked.gridColumns(in: .below), 1)
    }

    func test_detailPagePlan_keeping_dropsHiddenSectionsInOrder() {
        let plan = DetailPagePlan(top: [0], main: [1, 2, 3], side: [4], below: [5, 6])

        let kept = plan.keeping { $0 != 2 && $0 != 4 }

        XCTAssertEqual(kept, DetailPagePlan(top: [0], main: [1, 3], side: [], below: [5, 6]))
    }

    func test_detailPageHasPoster_blankPath_isFalse() {
        XCTAssertFalse(DetailHeroLayout.hasPoster("  "))
    }

    @MainActor
    func test_foldPanes_trailingPaneStartsLevelWithLeadingTitle() {
        // The title sits 40 pt down the leading pane, inside a stack and padding as in
        // the hero; the 100 pt trailing pane starts level with it, so the row is 140 tall.
        let panes = FoldPanesLayout(split: bentSplit) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 40)
                HStack(alignment: .top) {
                    Color.clear.frame(width: 10, height: 10)
                    Color.clear.frame(height: 60)
                        .alignmentGuide(.detailTitleTop) { $0[.top] }
                }
            }
            .padding(.horizontal, -DesignSpacing.lg)
            Color.clear.frame(height: 100)
        }

        let size = UIHostingController(rootView: panes).sizeThatFits(in: CGSize(width: 867, height: 2000))

        XCTAssertEqual(size.height, 140, accuracy: 0.5)
    }

    @MainActor
    func test_foldPanes_noTitleGuide_bothPanesStartAtTop() {
        let panes = FoldPanesLayout(split: bentSplit) {
            Color.clear.frame(height: 60)
            Color.clear.frame(height: 100)
        }

        let size = UIHostingController(rootView: panes).sizeThatFits(in: CGSize(width: 867, height: 2000))

        XCTAssertEqual(size.height, 100, accuracy: 0.5)
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

/// Each detail page's section plan: what goes where in each layout, and that every
/// section the page has is placed exactly once.
final class DetailPagePlanTests: XCTestCase {
    private let layouts: [DetailPageLayout] = [.stacked, .columns, .panes]

    /// What goes wrong placing `shown` in each layout: a section placed twice, a hidden
    /// one placed, or a shown one left out. The hero is drawn whole on top, or split into
    /// backdrop and identity across a fold, so only those parts count as shown.
    private func placementProblems<Section>(
        _ plan: (DetailPageLayout, Set<Section>) -> DetailPagePlan<Section>,
        shown: Set<Section>,
        heroParts: (all: Section, backdrop: Section, identity: Section)? = nil
    ) -> [String] {
        layouts.flatMap { layout -> [String] in
            let placed = plan(layout, shown).sections
            var expected = shown
            if let heroParts {
                expected.subtract(layout == .panes ? [heroParts.all] : [heroParts.backdrop, heroParts.identity])
            }
            var problems: [String] = []
            if placed.count != Set(placed).count { problems.append("\(layout) places a section twice") }
            if !Set(placed).isSubset(of: expected) { problems.append("\(layout) places a hidden section") }
            if !expected.isSubset(of: Set(placed)) { problems.append("\(layout) leaves a section out") }
            return problems
        }
    }

    // MARK: - Movie

    private let allMovie: Set<MovieDetailLayout.Section> = [
        .hero(.all), .hero(.backdrop), .hero(.identity), .rating, .logWatch, .storyline, .facts, .awards,
        .cast, .crew, .similar, .collection, .reviews, .attribution,
    ]

    func test_moviePlan_everyLayout_placesEachSectionOnce() {
        let problems = placementProblems(
            MovieDetailLayout.plan,
            shown: allMovie,
            heroParts: (.hero(.all), .hero(.backdrop), .hero(.identity))
        )

        XCTAssertEqual(problems, [])
    }

    func test_moviePlan_wideWithAwards_awardsBesideFactsInMain() {
        let plan = MovieDetailLayout.plan(for: .columns, showing: allMovie)

        XCTAssertEqual(plan.main, [.rating, .logWatch, .storyline, .facts])
        XCTAssertEqual(plan.side, [.awards])
    }

    func test_moviePlan_wideWithoutAwards_factsTakeSideColumn() {
        let plan = MovieDetailLayout.plan(for: .columns, showing: allMovie.subtracting([.awards]))

        XCTAssertEqual(plan.main, [.rating, .logWatch, .storyline])
        XCTAssertEqual(plan.side, [.facts])
    }

    func test_moviePlan_phone_keepsPhoneOrder() {
        let plan = MovieDetailLayout.plan(for: .stacked, showing: allMovie)

        XCTAssertEqual(
            plan.sections,
            [
                .hero(.all), .rating, .logWatch, .storyline, .facts, .awards,
                .cast, .crew, .similar, .collection, .reviews, .attribution,
            ]
        )
    }

    func test_moviePlan_panes_titleFactsAndStoryLeadAwardsAndCarouselsTrail() {
        let plan = MovieDetailLayout.plan(for: .panes, showing: allMovie)

        XCTAssertEqual(plan.top, [.hero(.backdrop)])
        XCTAssertEqual(plan.main, [.hero(.identity), .facts, .rating, .logWatch, .storyline, .reviews])
        XCTAssertEqual(plan.side, [.awards, .cast, .crew, .similar, .collection])
    }

    // MARK: - TV series

    private let allSeries: Set<TVSeriesLayout.Section> = [
        .hero(.all), .hero(.backdrop), .hero(.identity), .ratingAndStoryline, .awards, .carousels, .reviews,
        .attribution,
    ]

    func test_seriesPlan_everyLayout_placesEachSectionOnce() {
        let problems = placementProblems(
            TVSeriesLayout.plan,
            shown: allSeries,
            heroParts: (.hero(.all), .hero(.backdrop), .hero(.identity))
        )

        XCTAssertEqual(problems, [])
    }

    func test_seriesPlan_wideWithoutAwards_hasNoSideColumn() {
        let plan = TVSeriesLayout.plan(for: .columns, showing: allSeries.subtracting([.awards]))

        XCTAssertTrue(plan.side.isEmpty)
    }

    func test_seriesPlan_panes_reviewsLeadCarouselsTrail() {
        let plan = TVSeriesLayout.plan(for: .panes, showing: allSeries)

        XCTAssertEqual(plan.slot(of: .reviews), .main)
        XCTAssertEqual(plan.slot(of: .carousels), .side)
    }

    // MARK: - TV season

    private let allSeason: Set<TVSeasonLayout.Section> = [
        .hero(.all), .hero(.backdrop), .hero(.identity), .ratingAndOverview, .awards, .credits, .episodes,
        .attribution,
    ]

    func test_seasonPlan_everyLayout_placesEachSectionOnce() {
        let problems = placementProblems(
            TVSeasonLayout.plan,
            shown: allSeason,
            heroParts: (.hero(.all), .hero(.backdrop), .hero(.identity))
        )

        XCTAssertEqual(problems, [])
    }

    func test_seasonPlan_wide_episodesRunFullWidthBelow() {
        let plan = TVSeasonLayout.plan(for: .columns, showing: allSeason)

        XCTAssertEqual(plan.slot(of: .episodes), .below)
    }

    func test_seasonPlan_panes_episodesLeadEverythingElseTrails() {
        let plan = TVSeasonLayout.plan(for: .panes, showing: allSeason)

        XCTAssertEqual(plan.main, [.hero(.identity), .episodes])
        XCTAssertEqual(plan.side, [.ratingAndOverview, .awards, .credits])
    }

    // MARK: - TV episode

    private let allEpisode: Set<TVEpisodeLayout.Section> = [
        .hero(.all), .hero(.backdrop), .hero(.identity), .ratingAndOverview, .awards, .otherEpisodes, .credits,
        .attribution,
    ]

    func test_episodePlan_everyLayout_placesEachSectionOnce() {
        let problems = placementProblems(
            TVEpisodeLayout.plan,
            shown: allEpisode,
            heroParts: (.hero(.all), .hero(.backdrop), .hero(.identity))
        )

        XCTAssertEqual(problems, [])
    }

    func test_episodePlan_panes_moreEpisodesOpenTrailingPane() {
        let plan = TVEpisodeLayout.plan(for: .panes, showing: allEpisode)

        XCTAssertEqual(plan.side.first, .otherEpisodes)
    }

    // MARK: - Person

    private let allPerson: Set<PersonDetailLayout.Section> = [
        .header, .biography, .facts, .awards, .images, .credits,
    ]

    func test_personPlan_everyLayout_placesEachSectionOnce() {
        let problems = placementProblems(PersonDetailLayout.plan, shown: allPerson)

        XCTAssertEqual(problems, [])
    }

    func test_personPlan_wideWithoutFactsOrAwards_hasNoSideColumn() {
        let plan = PersonDetailLayout.plan(for: .columns, showing: [.header, .biography, .credits])

        XCTAssertTrue(plan.side.isEmpty)
        XCTAssertEqual(plan.below, [.credits])
    }

    func test_personPlan_panes_carouselsTrail() {
        let plan = PersonDetailLayout.plan(for: .panes, showing: allPerson)

        XCTAssertEqual(plan.main, [.header, .biography, .facts, .awards])
        XCTAssertEqual(plan.side, [.images, .credits])
    }
}
