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
/// column takes the full width instead of leaving a gap. Across the iPhone Duo's
/// fold the two columns take the two panes, with the crease as the gap.
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

    /// Where a fold crosses these columns, or nil.
    @State private var fold: FoldSplit?

    private var isSideBySide: Bool {
        twoColumns && showsSecondary
    }

    private var foldPanes: FoldSplit? {
        isSideBySide ? fold : nil
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: itemSpacing) {
                primary
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSecondary {
                VStack(alignment: .leading, spacing: itemSpacing) {
                    secondary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.carouselStaysInPane, foldPanes != nil)
        .onFoldSplitChange { fold = $0 }
    }

    private var layout: AnyLayout {
        if let foldPanes {
            AnyLayout(FoldPanesLayout(split: foldPanes))
        } else if isSideBySide {
            AnyLayout(
                SideBySideColumnsLayout(
                    secondaryWidth: DetailLayoutMetrics.secondaryWidth(forContentWidth: contentWidth),
                    spacing: DetailLayoutMetrics.columnSpacing
                )
            )
        } else {
            AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        }
    }
}

/// Two subviews top-aligned side by side: the second gets `secondaryWidth` on the
/// trailing edge, the first gets the rest. Each is measured once, at its column width
/// and natural height. An `HStack` would also work, but it measures each child at
/// several widths and again for alignment, and with deeply nested rows (a long awards
/// card) that repeated measuring grows fast enough to hang the page. Natural heights
/// also keep a card from stretching to the taller column.
private struct SideBySideColumnsLayout: Layout {
    let secondaryWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (secondaryWidth * 2 + spacing)
        let columns = DetailLayoutMetrics.columnWidths(
            totalWidth: width,
            secondaryWidth: secondaryWidth,
            spacing: spacing
        )
        let heights = zip(subviews, [columns.primary, columns.secondary]).map { subview, columnWidth in
            subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = DetailLayoutMetrics.columnWidths(
            totalWidth: bounds.width,
            secondaryWidth: secondaryWidth,
            spacing: spacing
        )
        if let primary = subviews.first {
            primary.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.primary, height: nil)
            )
        }
        if subviews.count > 1 {
            subviews[1].place(
                at: CGPoint(x: bounds.maxX - columns.secondary, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.secondary, height: nil)
            )
        }
    }
}
