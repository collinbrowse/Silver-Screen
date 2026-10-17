//
//  ContentWidthReader.swift
//  SilverScreen
//
//  Measures the width a screen is actually given (a split view or an iPad window,
//  not the device) so layouts can pick columns from it, plus the readable-column cap.
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

extension View {
    /// Caps a list or a scroll view's content at `ReadableWidth.maximum` and centers it.
    /// Layout keeps the column inside the safe area, so it centers beside an iPad
    /// sidebar rather than under it. No effect at phone widths.
    func readableColumn() -> some View {
        frame(maxWidth: ReadableWidth.maximum)
            .frame(maxWidth: .infinity)
    }
}
