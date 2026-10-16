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

    /// Margin on each side that centers a `maximum`-wide column in `width`.
    /// Zero whenever the column already fits, so phone layouts do not change.
    static func sideMargin(forWidth width: CGFloat) -> CGFloat {
        max(0, (width - maximum) / 2)
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
