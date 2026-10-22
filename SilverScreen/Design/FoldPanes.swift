//
//  FoldPanes.swift
//  SilverScreen
//
//  Reads the iPhone Duo's crease and keeps content off it while the hinge is bent
//  (book posture). Only the active crease counts: a fully open Duo is one flat screen
//  and gets the normal wide layout, with no gap left for the crease. Everything here
//  is a no-op on devices without a fold and on SDKs before iOS 27.1.
//

import SwiftUI

extension View {
    /// Reports where a fold crosses this view, in its own coordinates, or nil when
    /// none does. Measure a view whose size does not depend on the result.
    func onFoldSplitChange(_ action: @escaping (FoldSplit?) -> Void) -> some View {
        modifier(FoldSplitObserver(action: action))
    }

    /// Keeps this view inside one pane when a fold crosses the space it is offered,
    /// and leaves it as it is otherwise. Use it for controls and short text that must
    /// not sit on the crease (segmented controls, toasts, empty states, titles).
    func foldPane(_ pane: FoldPane = .leading, alignment: HorizontalAlignment = .center) -> some View {
        modifier(FoldPaneModifier(pane: pane, alignment: alignment))
    }
}

extension View {
    /// For a full-width section (a carousel or the reviews, which carry their own
    /// side padding) moved into a pane of `DetailColumns`: cancels the page's side
    /// padding so the section lines up with the pane's cards. The pane's margin from
    /// the crease is wider than that padding, so the section still stays off it.
    func inPane() -> some View {
        padding(.horizontal, -DesignSpacing.lg)
    }
}

extension View {
    /// The page's side padding for its `DetailColumns`. As the iPhone Duo's hinge
    /// panes directly under a `.backdrop`-only hero, the page stack's spacing is also
    /// taken back, so the `.identity` hero at the top of the leading pane sits where it
    /// would under a full hero.
    func detailColumnsInset(hingePanes: Bool) -> some View {
        padding(.horizontal, DesignSpacing.lg)
            .padding(.top, hingePanes ? -DesignSpacing.xl : 0)
    }
}

/// One side of a fold.
enum FoldPane: Sendable {
    case leading
    case trailing
}

private struct FoldSplitObserver: ViewModifier {
    let action: (FoldSplit?) -> Void

    func body(content: Content) -> some View {
        #if FOLD_SDK
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: FoldSplit?.self) { proxy in
                let divisions = proxy
                    .reservedRegions(kind: .division)
                    .map { region in
                        FoldDivision(
                            frame: region.frame,
                            leadingMargin: region.margins.leading,
                            trailingMargin: region.margins.trailing
                        )
                    }
                return FoldLayout.split(
                    bounds: CGRect(origin: .zero, size: proxy.size),
                    divisions: divisions
                )
            } action: { split in
                action(split)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct FoldPaneModifier: ViewModifier {
    let pane: FoldPane
    let alignment: HorizontalAlignment
    @State private var split: FoldSplit?

    func body(content: Content) -> some View {
        SinglePaneLayout(paneRect: paneRect, alignment: alignment) {
            content
        }
        .onFoldSplitChange { split = $0 }
    }

    private var paneRect: CGRect? {
        guard let split else { return nil }
        return pane == .leading ? split.leading : split.trailing
    }
}

/// Takes the full width it is offered and places its one subview inside
/// `paneRect` (offered the pane's width), or across the full width when there is no
/// pane, aligned by `alignment`. Its own width never depends on the pane, so
/// measuring it is stable, and a small centered view is still measured against the
/// whole row, where the crease can cross it.
private struct SinglePaneLayout: Layout {
    let paneRect: CGRect?
    let alignment: HorizontalAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        guard let width = proposal.width, width.isFinite else {
            return child.sizeThatFits(proposal)
        }
        let childWidth = paneRect?.width ?? width
        let size = child.sizeThatFits(ProposedViewSize(width: childWidth, height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let region = paneRect.map { $0.offsetBy(dx: bounds.minX, dy: 0) } ?? bounds
        let childProposal = ProposedViewSize(width: region.width, height: bounds.height)
        let childWidth = min(child.sizeThatFits(childProposal).width, region.width)
        let x: CGFloat = switch alignment {
            case .leading: region.minX
            case .trailing: region.maxX - childWidth
            default: region.minX + (region.width - childWidth) / 2
        }
        child.place(at: CGPoint(x: x, y: bounds.minY), proposal: childProposal)
    }
}

/// Two subviews in the two panes of `split`, top-aligned, each measured once at its
/// pane's width and natural height. Nothing is placed in the gutter.
struct FoldPanesLayout: Layout {
    let split: FoldSplit

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? split.trailing.maxX
        let heights = zip(subviews, [split.leading.width, split.trailing.width]).map { subview, paneWidth in
            subview.sizeThatFits(ProposedViewSize(width: paneWidth, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, pane) in zip(subviews, [split.leading, split.trailing]) {
            subview.place(
                at: CGPoint(x: bounds.minX + pane.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: pane.width, height: nil)
            )
        }
    }
}
