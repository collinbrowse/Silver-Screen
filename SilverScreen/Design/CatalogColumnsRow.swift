//
//  CatalogColumnsRow.swift
//  SilverScreen
//
//  One list row that holds several catalog cells side by side on wide screens.
//

import SwiftUI

/// Lays out one `CatalogGridRow` in `columns` equal-width slots. A short last row
/// keeps the same slot widths, so its cells line up with the rows above.
/// With one column this is just the cell, so phone lists render as before.
struct CatalogColumnsRow<Item, ID: Hashable, Cell: View>: View {
    let row: CatalogGridRow<Item, ID>
    let columns: Int
    let id: KeyPath<Item, ID>
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        if columns <= 1, let item = row.items.first {
            cell(item)
        } else {
            HStack(alignment: .top, spacing: CatalogGridMetrics.columnSpacing) {
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
        }
    }
}
