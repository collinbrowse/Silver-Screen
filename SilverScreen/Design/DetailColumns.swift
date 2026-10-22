//
//  DetailColumns.swift
//  SilverScreen
//
//  The shared frame of a detail page: measuring it, deciding its `DetailPageLayout`,
//  and laying its sections out from a `DetailPagePlan`, so each page only says which
//  sections it has and where they go.
//

import SwiftUI

/// A section of a detail page.
protocol DetailPageSection: Hashable {
    /// True for sections that keep their own side margin (the hero, carousels, review
    /// and episode lists), which run edge to edge. Other sections are cards, and the
    /// page insets them.
    var carriesOwnInset: Bool { get }
}

/// What a detail page lays out with, measured by `DetailPageReader`.
struct DetailPageGeometry: Equatable {
    let layout: DetailPageLayout
    /// Width of the page's content column; see `DetailLayoutMetrics.contentWidth`.
    let contentWidth: CGFloat
}

/// Builds a detail page with its `DetailPageGeometry`, from the width it is given
/// inside the safe area, the text size, and where a fold crosses it. `content` is the
/// page's scroll view. The width starts at zero for the first frame, which lays out
/// as a stacked page.
struct DetailPageReader<Content: View>: View {
    @ViewBuilder let content: (DetailPageGeometry) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Larger text needs a wider page before two columns fit.
    @ScaledMetric(relativeTo: .body) private var twoColumnMinimumWidth = DetailLayoutMetrics.twoColumnMinimumWidth
    @State private var width: CGFloat = 0
    @State private var fold: FoldSplit?

    var body: some View {
        let layout = DetailPageLayout.resolve(
            width: width,
            fold: fold,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            twoColumnMinimumWidth: twoColumnMinimumWidth
        )
        content(DetailPageGeometry(layout: layout, contentWidth: layout.contentWidth(forWidth: width)))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
            } action: { newWidth in
                width = newWidth
            }
            .onFoldSplitChange { fold = $0 }
    }
}

/// Lays a detail page's sections out from `plan`: `top` full width, then the main and
/// side columns (stacked on a phone, side by side on a wide page, one per pane across
/// a fold), then `below` full width. Cards get the page's side inset; sections that
/// carry their own inset run edge to edge. Every section is `xl` from the next.
/// `section` draws one section, told its slot so a grid can pick its columns.
struct DetailPageSections<Section: DetailPageSection, SectionContent: View>: View {
    let page: DetailPageGeometry
    let plan: DetailPagePlan<Section>
    @ViewBuilder let section: (Section, DetailSlot) -> SectionContent

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xl) {
            // Across a fold the leading pane picks up right under the top sections: the
            // hero draws its backdrop on top and its poster and title in the pane.
            VStack(alignment: .leading, spacing: page.layout == .panes ? 0 : DesignSpacing.xl) {
                ForEach(plan.top, id: \.self) { fullWidth($0, in: .top) }
                if !plan.main.isEmpty || !plan.side.isEmpty {
                    DetailColumns(
                        layout: page.layout,
                        contentWidth: page.contentWidth,
                        showsSecondary: !plan.side.isEmpty
                    ) {
                        ForEach(plan.main, id: \.self) { inColumn($0, in: .main) }
                    } secondary: {
                        ForEach(plan.side, id: \.self) { inColumn($0, in: .side) }
                    }
                    .padding(.horizontal, DesignSpacing.lg)
                }
            }
            ForEach(plan.below, id: \.self) { fullWidth($0, in: .below) }
        }
    }

    /// A section in a column, which already has the page's inset: one that carries its
    /// own takes the column's back, so it lines up with the cards beside it. A fold
    /// pane's margin from the crease is wider than that inset, so it stays off the crease.
    @ViewBuilder
    private func inColumn(_ item: Section, in slot: DetailSlot) -> some View {
        if item.carriesOwnInset {
            section(item, slot)
                .padding(.horizontal, -DesignSpacing.lg)
        } else {
            section(item, slot)
        }
    }

    @ViewBuilder
    private func fullWidth(_ item: Section, in slot: DetailSlot) -> some View {
        if item.carriesOwnInset {
            section(item, slot)
        } else {
            section(item, slot)
                .padding(.horizontal, DesignSpacing.lg)
        }
    }
}

extension VerticalAlignment {
    private enum DetailTitleTop: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.top]
        }
    }

    /// The top of a detail page's title block. When the main column starts with the
    /// title (the hero's identity across a fold), the side column starts level with it.
    static let detailTitleTop = VerticalAlignment(DetailTitleTop.self)
}

extension LayoutSubview {
    /// How far below this subview's top its `detailTitleTop` guide sits at `width`,
    /// or 0 when nothing inside it sets one.
    func detailTitleTop(atWidth width: CGFloat) -> CGFloat {
        dimensions(in: ProposedViewSize(width: width, height: nil))[explicit: .detailTitleTop] ?? 0
    }
}

/// Lays `primary` and `secondary` out stacked, side by side, or one per fold pane, as
/// `layout` says. `AnyLayout` keeps each section's identity across the switch, so an
/// expanded storyline stays expanded when the device rotates or unfolds. Pass
/// `showsSecondary: false` when the side column would be empty, so the main column
/// takes the full width instead of leaving a gap.
struct DetailColumns<Primary: View, Secondary: View>: View {
    let layout: DetailPageLayout
    let contentWidth: CGFloat
    var showsSecondary: Bool = true
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    /// Where a fold crosses these columns, or nil.
    @State private var fold: FoldSplit?

    private var isSideBySide: Bool {
        layout.isSideBySide && showsSecondary
    }

    /// The panes to lay the columns into. The page decided on panes from its own
    /// reading; until this view's reading agrees, the columns sit side by side.
    private var foldPanes: FoldSplit? {
        isSideBySide && layout == .panes ? fold : nil
    }

    var body: some View {
        columnsLayout {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                primary
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSecondary {
                VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                    secondary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.carouselStaysInPane, foldPanes != nil)
        .foldTransitionIdentity(isSplit: foldPanes != nil)
        .onFoldSplitChange { fold = $0 }
    }

    private var columnsLayout: AnyLayout {
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
            AnyLayout(VStackLayout(alignment: .leading, spacing: DesignSpacing.xl))
        }
    }
}

/// Two subviews top-aligned side by side: the second gets `secondaryWidth` on the
/// trailing edge, the first gets the rest. Each is measured once, at its column width
/// and natural height. An `HStack` would also work, but it measures each child at
/// several widths and again for alignment, and with deeply nested rows (a long awards
/// card) that repeated measuring grows fast enough to hang the page. Natural heights
/// also keep a card from stretching to the taller column. The second starts level
/// with the first's `detailTitleTop`, when it has one.
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
        let tops = secondaryTop(subviews, primaryWidth: columns.primary)
        let heights = zip(subviews, [columns.primary, columns.secondary]).map { subview, columnWidth in
            subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        return CGSize(width: width, height: zip(heights, tops).map(+).max() ?? 0)
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
            let top = secondaryTop(subviews, primaryWidth: columns.primary)[1]
            subviews[1].place(
                at: CGPoint(x: bounds.maxX - columns.secondary, y: bounds.minY + top),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.secondary, height: nil)
            )
        }
    }

    /// Top offsets for the two columns.
    private func secondaryTop(_ subviews: Subviews, primaryWidth: CGFloat) -> [CGFloat] {
        [0, subviews.first?.detailTitleTop(atWidth: primaryWidth) ?? 0]
    }
}
