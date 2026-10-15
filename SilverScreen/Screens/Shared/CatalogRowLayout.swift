//
//  CatalogRowLayout.swift
//  SilverScreen
//
//  A catalog row with its trailing control (the watched eye, or the list button
//  for people). At accessibility text sizes the control moves under the row's
//  details so the title and genres get the full width instead of wrapping early.
//

import SwiftUI

struct CatalogRowLayout<Row: View, Control: View>: View {
    /// Must match the density of the `CatalogRowView` inside `row`, so the stacked
    /// control lines up with the text column rather than the artwork.
    var density: CatalogRowView.Density = .standard
    @ViewBuilder let row: Row
    @ViewBuilder let control: Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        // AnyLayout keeps the control's identity when the text size changes, so a
        // pending confirmation or optimistic watched state is not reset.
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DesignSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DesignSpacing.sm))

        layout {
            row
                // Row insets assume the control's own margin on the right; without it
                // stacked text would run to 8 pt from the edge.
                .padding(.trailing, isStacked ? DesignSpacing.sm : 0)
            control
                .padding(.leading, isStacked ? CatalogRowView.detailsLeading(for: density) : 0)
        }
    }
}
