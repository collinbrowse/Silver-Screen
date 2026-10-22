//
//  CatalogColumnsRow.swift
//  SilverScreen
//
//  One list row that holds several catalog cells side by side on wide screens.
//

import SwiftUI

/// Builds a catalog list with its column count (`CatalogGridMetrics.columnCount`),
/// from the width it is given, the text size, and whether a fold crosses it.
/// `singleColumn` forces one column (Library's edit mode, where rows drag whole).
struct CatalogColumnsReader<Content: View>: View {
    var singleColumn = false
    @ViewBuilder let content: (Int) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Larger text needs wider rows before a title wraps after every word.
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth = CatalogGridMetrics.minimumColumnWidth
    @State private var fold: FoldSplit?

    var body: some View {
        // Read here, in this view's own body, so a change re-renders the list; a read
        // only inside the width reader's closure would not.
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let minimumColumnWidth = minimumColumnWidth
        let fold = fold
        let singleColumn = singleColumn
        return ContentWidthReader { width in
            content(
                singleColumn
                    ? 1
                    : CatalogGridMetrics.columnCount(
                        forWidth: width,
                        isFolded: fold != nil,
                        isAccessibilitySize: isAccessibilitySize,
                        minimumColumnWidth: minimumColumnWidth
                    )
            )
        }
        .onFoldSplitChange { self.fold = $0 }
    }
}

/// Lays out one `CatalogGridRow` in `columns` equal-width slots. A short last row
/// keeps the same slot widths, so its cells line up with the rows above.
/// With one column this is just the cell, so phone lists render as before. Across
/// the iPhone Duo's fold, the two columns sit on either side of the crease;
/// `CatalogColumnsReader` gives a folded list two columns.
struct CatalogColumnsRow<Item, ID: Hashable, Cell: View>: View {
    let row: CatalogGridRow<Item, ID>
    let columns: Int
    let id: KeyPath<Item, ID>
    @ViewBuilder let cell: (Item) -> Cell

    /// Where a fold crosses this row (iPhone Duo opened sideways), or nil.
    @State private var fold: FoldSplit?

    var body: some View {
        if columns <= 1, let item = row.items.first {
            cell(item)
        } else {
            columnsLayout {
                ForEach(row.items, id: id) { item in
                    cell(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(row.items.count..<max(columns, row.items.count), id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: 0)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .foldTransitionIdentity(isSplit: fold != nil)
            // A separator would run across the crease; the panes' spacing separates rows.
            .listRowSeparator(fold == nil ? .automatic : .hidden)
            .onFoldSplitChange { fold = $0 }
        }
    }

    /// Two columns across a fold sit one per pane, with the crease as the gap, so no
    /// title, poster, or watched control lands on it. Otherwise the columns share
    /// the row evenly.
    private var columnsLayout: AnyLayout {
        if columns == 2, let fold {
            AnyLayout(FoldPanesLayout(split: fold))
        } else {
            AnyLayout(HStackLayout(alignment: .top, spacing: CatalogGridMetrics.columnSpacing))
        }
    }
}
