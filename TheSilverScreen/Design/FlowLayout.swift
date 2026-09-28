//
//  FlowLayout.swift
//  TheSilverScreen
//

import SwiftUI

/// Wrapping horizontal layout for chips and similar tag rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, item) in result.items.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: item.proposal
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, items: [(origin: CGPoint, proposal: ProposedViewSize)]) {
        let maxWidth = proposal.width ?? .infinity
        // Measure against the proposed row width. An unspecified measure lets one
        // long chip report its full ideal width, and the parent then centers that
        // overflow and clips both screen edges.
        let itemProposal: ProposedViewSize = maxWidth.isFinite
            ? ProposedViewSize(width: maxWidth, height: nil)
            : .unspecified
        var items: [(origin: CGPoint, proposal: ProposedViewSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(itemProposal)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append((CGPoint(x: x, y: y), itemProposal))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }

        if maxWidth.isFinite {
            width = min(width, maxWidth)
        }

        return (CGSize(width: width, height: y + rowHeight), items)
    }
}
