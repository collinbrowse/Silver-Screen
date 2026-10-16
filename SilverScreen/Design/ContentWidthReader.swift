//
//  ContentWidthReader.swift
//  SilverScreen
//
//  Measures the width a screen is actually given (a split view or an iPad window,
//  not the device) so layouts can pick columns and margins from it.
//

import SwiftUI

/// Builds `content` with its own width inside the safe area. The width starts at
/// zero for the first frame, which every metric treats as the one-column layout.
struct ContentWidthReader<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var width: CGFloat = 0

    var body: some View {
        content(width)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
            } action: { newWidth in
                width = newWidth
            }
    }
}

/// Centers a list's or scroll view's content in a `ReadableWidth.maximum` column
/// once the view is wider than that. The scroll indicator and background stay at
/// the edges.
private struct ReadableContentMargins: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, ReadableWidth.sideMargin(forWidth: width), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }
}

extension View {
    /// Keeps a text-heavy list or scroll view at a readable width on wide screens.
    /// No effect at phone widths.
    func readableContentMargins() -> some View {
        modifier(ReadableContentMargins())
    }

    /// Caps a scroll view's content column at `ReadableWidth.maximum` and centers it.
    func readableColumn() -> some View {
        frame(maxWidth: ReadableWidth.maximum)
            .frame(maxWidth: .infinity)
    }
}
