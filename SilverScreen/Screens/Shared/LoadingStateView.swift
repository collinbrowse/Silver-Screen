//
//  LoadingStateView.swift
//  SilverScreen
//
//  The full-screen loading state every screen shows while its first load is in flight:
//  the app icon's film winding on its reel, centered.
//

import SwiftUI

/// Fills the screen with the reel loader while a screen's first load runs. Reused by every
/// screen's `.idle, .loading` case, like `EmptyStateView` and `ErrorStateView`.
struct LoadingStateView: View {
    /// The loader's width; about a third of an iPhone screen.
    static let loaderWidth: CGFloat = 128

    var body: some View {
        ReelLoader()
            .frame(width: Self.loaderWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadingStateView()
}
