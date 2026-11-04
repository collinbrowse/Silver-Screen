//
//  TourAnchorModifier.swift
//  SilverScreen
//
//  How a view takes part in the feature tour: it reports its window frame so
//  the overlay can cut it out, and a scrolling screen brings it into view.
//

import SwiftUI

extension View {
    /// Marks this view as something the tour can highlight. Nil leaves it unmarked,
    /// for rows where only some items are tour targets.
    func tourAnchor(_ anchor: TourAnchor?) -> some View {
        modifier(TourAnchorModifier(anchor: anchor))
    }

    /// Scrolls the current stop's anchor to the middle of a detail screen. Apply it
    /// inside the screen's `ScrollViewReader`; the anchor view needs `.id(anchor.scrollID)`.
    func tourScrolls(with proxy: ScrollViewProxy) -> some View {
        modifier(TourScrollModifier(proxy: proxy))
    }
}

/// Reports frame and visibility to the `TourController` in the environment, if any.
struct TourAnchorModifier: ViewModifier {
    let anchor: TourAnchor?
    @Environment(TourController.self) private var tour: TourController?
    /// Tells this view apart from another one carrying the same anchor mid-relayout.
    @State private var source = UUID()

    func body(content: Content) -> some View {
        if let anchor {
            reporting(content, as: anchor)
        } else {
            content
        }
    }

    private func reporting(_ content: Content, as anchor: TourAnchor) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                tour?.report(anchor, source: source, frame: frame, isVisible: nil)
            }
            .onAppear { tour?.report(anchor, source: source, frame: nil, isVisible: true) }
            .onDisappear { tour?.report(anchor, source: source, frame: nil, isVisible: false) }
    }
}

/// Keeps scrolling to the anchor until it has loaded and reported a frame, and again
/// whenever the screen changes size. Folding or unfolding a phone relays the page out
/// around the old scroll offset, which can leave the anchor off screen. The tour
/// overlay blocks touches, so repeating the scroll never fights the user.
struct TourScrollModifier: ViewModifier {
    let proxy: ScrollViewProxy
    @Environment(TourController.self) private var tour: TourController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero

    /// Restarts the scroll when the stop or the screen size changes.
    private struct Trigger: Equatable {
        let stop: TourStop?
        let size: CGSize
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .task(id: Trigger(stop: tour?.current, size: size)) {
                guard let tour, let anchor = tour.current?.scrollAnchor else { return }
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        proxy.scrollTo(anchor.scrollID, anchor: .center)
                    }
                    if tour.isShowing(anchor) { return }
                }
            }
    }
}
