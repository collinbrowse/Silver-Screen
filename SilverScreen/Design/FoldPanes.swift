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

/// One side of a fold.
enum FoldPane: Sendable {
    case leading
    case trailing
}

/// When a change in the fold should animate. The system animates opening, closing,
/// and rotating the Duo, which change the window's size; bending the hinge does not
/// change the window, so the crease appearing or going away is ours to animate.
enum FoldTransition {
    /// Slides content to its new pane. About as long as a system resize.
    static let animation = Animation.smooth(duration: 0.35)
    /// Under Reduce Motion: a short cross-fade instead of moving content.
    static let reducedMotionAnimation = Animation.easeInOut(duration: 0.25)

    /// The animation for a new fold reading, or nil to apply it as is. `previous` is
    /// nil before the first reading, so a screen's first layout never animates, and a
    /// split that only moves (rotation, resizing) is left to the system's own animation.
    static func animation(previous: FoldSplit??, next: FoldSplit?, reduceMotion: Bool) -> Animation? {
        guard let previous else { return nil }
        guard (previous == nil) != (next == nil) else { return nil }
        return reduceMotion ? reducedMotionAnimation : animation
    }
}

extension View {
    /// Under Reduce Motion, replaces this view with a cross-fade when a fold appears
    /// or goes away, instead of sliding its parts to new panes. No effect otherwise.
    func foldTransitionIdentity(isSplit: Bool) -> some View {
        modifier(FoldTransitionIdentity(isSplit: isSplit))
    }
}

private struct FoldTransitionIdentity: ViewModifier {
    let isSplit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .id(isSplit)
                .transition(.opacity)
        } else {
            content
        }
    }
}

private struct FoldSplitObserver: ViewModifier {
    let action: (FoldSplit?) -> Void
    /// The last reading reported, or nil before the first one.
    @State private var lastReported: FoldSplit??
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                report(split)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }

    private func report(_ split: FoldSplit?) {
        let animation = FoldTransition.animation(previous: lastReported, next: split, reduceMotion: reduceMotion)
        lastReported = .some(split)
        if let animation {
            withAnimation(animation) {
                action(split)
            }
        } else {
            action(split)
        }
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
        .foldTransitionIdentity(isSplit: split != nil)
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

/// Two subviews in the two panes of `split`, each measured once at its pane's width
/// and natural height. Nothing is placed in the gutter. Both start at the top, except
/// that the trailing one starts level with the leading one's `detailTitleTop` when it
/// has one (a detail page whose leading pane opens with the title).
struct FoldPanesLayout: Layout {
    let split: FoldSplit

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? split.trailing.maxX
        let tops = paneTops(subviews)
        let heights = zip(subviews, [split.leading.width, split.trailing.width]).map { subview, paneWidth in
            subview.sizeThatFits(ProposedViewSize(width: paneWidth, height: nil)).height
        }
        return CGSize(width: width, height: zip(heights, tops).map(+).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, (pane, top)) in zip(subviews, zip([split.leading, split.trailing], paneTops(subviews))) {
            subview.place(
                at: CGPoint(x: bounds.minX + pane.minX, y: bounds.minY + top),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: pane.width, height: nil)
            )
        }
    }

    private func paneTops(_ subviews: Subviews) -> [CGFloat] {
        [0, subviews.first?.detailTitleTop(atWidth: split.leading.width) ?? 0]
    }
}
