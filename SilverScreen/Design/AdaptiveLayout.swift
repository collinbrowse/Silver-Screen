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

    /// Whether a page `width` points wide (inside the safe area) uses two columns.
    /// Accessibility text sizes keep one column so long labels have the full width.
    static func usesTwoColumns(forWidth width: CGFloat, isAccessibilitySize: Bool) -> Bool {
        !isAccessibilitySize && width >= twoColumnMinimumWidth
    }

    /// Width of the page's content column: the readable cap on one column, the wider
    /// cap on two. Before the page is measured (`width` 0) this is the readable cap,
    /// so the first frame lays out as a phone page rather than collapsing.
    static func contentWidth(forWidth width: CGFloat, twoColumns: Bool) -> CGFloat {
        guard width > 0 else { return ReadableWidth.maximum }
        return min(width, twoColumns ? maximumContentWidth : ReadableWidth.maximum)
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

    static func heroAspectRatio(twoColumns: Bool) -> CGFloat {
        twoColumns ? wideHeroAspectRatio : compactHeroAspectRatio
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
