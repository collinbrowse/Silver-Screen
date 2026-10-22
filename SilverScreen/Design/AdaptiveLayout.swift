//
//  AdaptiveLayout.swift
//  SilverScreen
//
//  Width-driven layout decisions for large screens. Every answer depends on the
//  width a view is laid out in (an iPhone, the iPhone Duo's inner screen, an iPad
//  window or a split view), never on the device model, so one set of views serves
//  them all. A phone-width screen always gets the one-column layout it had before.
//

import CoreGraphics

/// How many catalog rows (artwork, details, watched control) sit side by side.
enum CatalogGridMetrics {
    /// Narrowest a catalog row gets before its title wraps after every word.
    /// 300 pt keeps every iPhone in portrait at one column and gives the iPhone Duo's
    /// 669 pt inner screen two.
    static let minimumColumnWidth: CGFloat = 300
    static let columnSpacing: CGFloat = DesignSpacing.lg
    /// Rows carry a lot of text, so a full-width 13" iPad still stops at three.
    static let maximumColumns = 3

    /// Columns that fit in `width` (the list's width inside the safe area).
    /// Accessibility text sizes stack each row's control under its details, which
    /// needs the whole width, so they always get one column.
    static func columnCount(forWidth width: CGFloat, isAccessibilitySize: Bool) -> Int {
        guard !isAccessibilitySize, width > 0 else { return 1 }
        let fitting = Int((width + columnSpacing) / (minimumColumnWidth + columnSpacing))
        return min(max(fitting, 1), maximumColumns)
    }
}

/// How many Search-home shelf cards (award ceremonies, genres) sit in one row.
enum ShelfGridMetrics {
    static let minimumCardWidth: CGFloat = 160
    static let cardSpacing: CGFloat = DesignSpacing.md
    /// Horizontal padding on each side of the shelf grid.
    static let sideInset: CGFloat = DesignSpacing.lg
    /// Phones have always shown two cards a row; never drop below that.
    static let minimumColumns = 2
    static let maximumColumns = 6

    /// Columns for a shelf grid in a container `width` points wide.
    static func columnCount(forWidth width: CGFloat) -> Int {
        let available = width - sideInset * 2
        guard available > 0 else { return minimumColumns }
        let fitting = Int((available + cardSpacing) / (minimumCardWidth + cardSpacing))
        return min(max(fitting, minimumColumns), maximumColumns)
    }
}

/// How many items a capped horizontal carousel (a person's credit rows) shows before
/// View All. Phones keep five; wider pages show about twice the cards that fit on
/// screen, so a wide carousel is not done after a single swipe.
enum CarouselMetrics {
    /// The phone preview: what every carousel showed before wide layouts.
    static let compactPreviewCount = 5
    /// View All never appears for this many items or fewer.
    static let viewAllMinimumCount = 10
    /// Matches `DetailCarousel`'s card spacing and side inset.
    static let cardSpacing: CGFloat = DesignSpacing.md
    static let sideInset: CGFloat = DesignSpacing.lg

    /// Cards wholly visible in a carousel `width` points wide.
    static func visibleCardCount(forWidth width: CGFloat, cardWidth: CGFloat) -> Int {
        let available = width - sideInset * 2
        guard available > 0, cardWidth > 0 else { return 0 }
        return Int((available + cardSpacing) / (cardWidth + cardSpacing))
    }

    /// Items to show before View All: twice the visible cards, never fewer than the phone's five.
    static func previewCount(forWidth width: CGFloat, cardWidth: CGFloat) -> Int {
        max(compactPreviewCount, visibleCardCount(forWidth: width, cardWidth: cardWidth) * 2)
    }

    /// View All appears once the items outnumber both the preview and the minimum.
    static func showsViewAll(totalCount: Int, previewCount: Int) -> Bool {
        totalCount > max(viewAllMinimumCount, previewCount)
    }
}

/// The widest a text-heavy column grows, so lines stay readable on wide screens.
enum ReadableWidth {
    /// Matches the cap Movie and Person detail already used.
    static let maximum: CGFloat = 700
}

/// How a detail page (movie, series, season, episode, person) uses a wide screen:
/// a wider hero and a second column beside the main text, instead of one stretched
/// column. Below the breakpoint the page keeps its phone layout.
enum DetailLayoutMetrics {
    /// Narrowest page that gets two columns. The iPhone Duo's inner screen in
    /// landscape and every iPad window wider than a third qualify; the inner screen
    /// in portrait (669 pt) stays one column.
    static let twoColumnMinimumWidth: CGFloat = 760
    /// Two-column pages stop growing here, so a 13" iPad does not spread them thin.
    static let maximumContentWidth: CGFloat = 1180
    static let columnSpacing: CGFloat = DesignSpacing.xl
    /// The side column takes this share of the page, up to `maximumSecondaryWidth`.
    static let secondaryShare: CGFloat = 0.42
    static let maximumSecondaryWidth: CGFloat = 360
    /// Phone hero shape.
    static let compactHeroAspectRatio: CGFloat = 16.0 / 9.0
    /// Wide hero shape: a full-width 16:9 backdrop would fill most of a landscape screen.
    static let wideHeroAspectRatio: CGFloat = 21.0 / 9.0

    /// Narrowest fold pane a detail page lays a column into: about a phone's width,
    /// which is what every section is built for. A narrower pane keeps the page whole.
    static let minimumPaneWidth: CGFloat = 300

    /// Whether a page `width` points wide (inside the safe area) uses two columns.
    /// Accessibility text sizes keep one column so long labels have the full width.
    /// `minimumWidth` is `twoColumnMinimumWidth` scaled with the text size.
    static func usesTwoColumns(
        forWidth width: CGFloat,
        isAccessibilitySize: Bool,
        minimumWidth: CGFloat = twoColumnMinimumWidth
    ) -> Bool {
        !isAccessibilitySize && width >= minimumWidth
    }

    /// Width of the page's content column: the readable cap on one column, the wider
    /// cap on two. Before the page is measured (`width` 0) this is the readable cap,
    /// so the first frame lays out as a phone page rather than collapsing.
    static func contentWidth(forWidth width: CGFloat, twoColumns: Bool) -> CGFloat {
        guard width > 0 else { return ReadableWidth.maximum }
        return min(width, columnCap(twoColumns: twoColumns))
    }

    /// The cap to apply to a scroll view's content column. A scroll view offers its
    /// content the full width, safe area included, so capping at the measured width
    /// would center a narrower column and stop the hero short of the screen edge.
    static func columnCap(twoColumns: Bool) -> CGFloat {
        twoColumns ? maximumContentWidth : ReadableWidth.maximum
    }

    /// Side column width for a two-column page whose content is `contentWidth` wide,
    /// after the page's side insets.
    static func secondaryWidth(forContentWidth contentWidth: CGFloat) -> CGFloat {
        let available = contentWidth - DesignSpacing.lg * 2 - columnSpacing
        return min(maximumSecondaryWidth, max(0, available * secondaryShare))
    }

    /// Main and side column widths in a two-column row `totalWidth` wide. The side
    /// column never takes more than the row leaves after the spacing.
    static func columnWidths(
        totalWidth: CGFloat,
        secondaryWidth: CGFloat,
        spacing: CGFloat
    ) -> (primary: CGFloat, secondary: CGFloat) {
        let secondary = min(secondaryWidth, max(0, totalWidth - spacing))
        return (max(0, totalWidth - secondary - spacing), secondary)
    }

    static func heroAspectRatio(twoColumns: Bool) -> CGFloat {
        twoColumns ? wideHeroAspectRatio : compactHeroAspectRatio
    }
}

/// How a detail page (movie, series, season, episode, person) uses its space. The
/// page decides this once, from its width, the text size, and whether a fold crosses
/// it; where each section goes then comes from the page's `DetailPagePlan`.
enum DetailPageLayout: Equatable, Sendable {
    /// One column: phones, narrow windows, accessibility text sizes.
    case stacked
    /// A main column and a narrower side column, with wide sections (carousels,
    /// reviews) full width below them: iPad, and the iPhone Duo's inner screen in landscape.
    case columns
    /// The iPhone Duo's hinge is bent: one column in each pane, with the crease as the gutter.
    case panes

    /// A fold wins whenever both panes are wide enough for a column, at any width or
    /// text size, since nothing may sit on the crease. Otherwise the width decides.
    static func resolve(
        width: CGFloat,
        fold: FoldSplit?,
        isAccessibilitySize: Bool,
        twoColumnMinimumWidth: CGFloat = DetailLayoutMetrics.twoColumnMinimumWidth
    ) -> DetailPageLayout {
        if let fold, min(fold.leading.width, fold.trailing.width) >= DetailLayoutMetrics.minimumPaneWidth {
            return .panes
        }
        let twoColumns = DetailLayoutMetrics.usesTwoColumns(
            forWidth: width,
            isAccessibilitySize: isAccessibilitySize,
            minimumWidth: twoColumnMinimumWidth
        )
        return twoColumns ? .columns : .stacked
    }

    /// True when the page has two columns side by side.
    var isSideBySide: Bool {
        self != .stacked
    }

    var heroAspectRatio: CGFloat {
        DetailLayoutMetrics.heroAspectRatio(twoColumns: isSideBySide)
    }

    /// See `DetailLayoutMetrics.columnCap(twoColumns:)`.
    var columnCap: CGFloat {
        DetailLayoutMetrics.columnCap(twoColumns: isSideBySide)
    }

    func contentWidth(forWidth width: CGFloat) -> CGFloat {
        DetailLayoutMetrics.contentWidth(forWidth: width, twoColumns: isSideBySide)
    }

    /// Items per row for a grid section (reviews, episodes) placed in `slot`: two
    /// across the full width of a two-column page, one in a column or on a phone.
    func gridColumns(in slot: DetailSlot) -> Int {
        self == .columns && slot == .below ? 2 : 1
    }
}

/// Where a section of a detail page sits.
enum DetailSlot: Equatable, Sendable {
    /// Full width above the columns: the hero.
    case top
    /// The main column (the leading pane across a fold).
    case main
    /// The side column (the trailing pane across a fold). On a stacked page it follows the main column.
    case side
    /// Full width below the columns.
    case below
}

/// Where each section of a detail page goes for one `DetailPageLayout`, in order.
/// Pages build their plan as a pure function of the layout, so placements are unit
/// tested instead of living in view branches. A stacked page reads the slots top to
/// bottom, so one plan serves both `.stacked` and `.columns`.
struct DetailPagePlan<Section: Hashable>: Equatable {
    var top: [Section] = []
    var main: [Section] = []
    var side: [Section] = []
    var below: [Section] = []

    /// Every placed section, in reading order.
    var sections: [Section] {
        top + main + side + below
    }

    /// The slot `section` is placed in, or nil when it is not placed.
    func slot(of section: Section) -> DetailSlot? {
        if top.contains(section) { return .top }
        if main.contains(section) { return .main }
        if side.contains(section) { return .side }
        if below.contains(section) { return .below }
        return nil
    }

    /// The plan without the sections the page has nothing to show for, order kept.
    func keeping(_ isShown: (Section) -> Bool) -> DetailPagePlan {
        DetailPagePlan(
            top: top.filter(isShown),
            main: main.filter(isShown),
            side: side.filter(isShown),
            below: below.filter(isShown)
        )
    }
}

/// One list row of up to `columns` catalog items laid side by side.
struct CatalogGridRow<Item, ID: Hashable>: Identifiable {
    /// The first item's id, so a row keeps its identity (and each control's
    /// pending state) when items around it change.
    let id: ID
    let items: [Item]
    let isFirst: Bool
    let isLast: Bool
}

/// Splits a flat catalog into list rows for a multi-column layout.
enum CatalogGrid {
    /// Groups `items` into rows of `columns`, in reading order. The last row may be short.
    /// One column yields one row per item, which is the phone layout unchanged.
    static func rows<Item, ID: Hashable>(
        _ items: [Item],
        columns: Int,
        id: KeyPath<Item, ID>
    ) -> [CatalogGridRow<Item, ID>] {
        let size = max(columns, 1)
        let starts = Array(stride(from: 0, to: items.count, by: size))
        return starts.enumerated().map { rowIndex, start in
            let slice = Array(items[start..<min(start + size, items.count)])
            return CatalogGridRow(
                id: slice[0][keyPath: id],
                items: slice,
                isFirst: rowIndex == 0,
                isLast: rowIndex == starts.count - 1
            )
        }
    }
}
