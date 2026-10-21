//
//  DetailColumns.swift
//  SilverScreen
//
//  Main and side sections of a detail page, side by side on wide screens.
//

import SwiftUI

/// Lays `primary` and `secondary` out side by side when `twoColumns` is true, and
/// stacked otherwise. `AnyLayout` keeps each section's identity across the switch,
/// so an expanded storyline stays expanded when the device rotates or unfolds.
/// Pass `showsSecondary: false` when the side column would be empty, so the main
/// column takes the full width instead of leaving a gap.
struct DetailColumns<Primary: View, Secondary: View>: View {
    let twoColumns: Bool
    let contentWidth: CGFloat
    var showsSecondary: Bool = true
    /// Between the main and side groups when they stack.
    var spacing: CGFloat = DesignSpacing.xl
    /// Between the sections inside each group.
    var itemSpacing: CGFloat = DesignSpacing.xl
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    private var isSideBySide: Bool {
        twoColumns && showsSecondary
    }

    var body: some View {
        let layout = isSideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: DetailLayoutMetrics.columnSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))

        layout {
            VStack(alignment: .leading, spacing: itemSpacing) {
                primary
            }
            // Side by side, the stack offers each column the row's full height; keep each
            // at its natural height so a card with a flexible divider does not stretch.
            .fixedSize(horizontal: false, vertical: isSideBySide)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSecondary {
                VStack(alignment: .leading, spacing: itemSpacing) {
                    secondary
                }
                .fixedSize(horizontal: false, vertical: isSideBySide)
                .frame(
                    width: isSideBySide
                        ? DetailLayoutMetrics.secondaryWidth(forContentWidth: contentWidth)
                        : nil,
                    alignment: .leading
                )
                .frame(maxWidth: isSideBySide ? nil : .infinity, alignment: .leading)
            }
        }
    }
}
