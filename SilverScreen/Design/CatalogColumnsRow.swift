//
//  CatalogColumnsRow.swift
//  SilverScreen
//
//  One list row that holds several catalog cells side by side on wide screens.
//

import SwiftUI

/// Lays out one `CatalogGridRow` in `columns` equal-width slots. A short last row
/// keeps the same slot widths, so its cells line up with the rows above.
/// With one column this is just the cell, so phone lists render as before. Across
/// the iPhone Duo's fold, the two columns sit on either side of the crease.
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
