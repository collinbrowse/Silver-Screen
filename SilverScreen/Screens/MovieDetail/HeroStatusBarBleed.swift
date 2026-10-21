//
//  HeroStatusBarBleed.swift
//  SilverScreen
//

import SwiftUI
import UIKit

extension View {
    /// Draws the backdrop under the status icons, with a short fade that is darker at the top.
    /// The fade lifts once the inline title has moved into the bar. Toolbar buttons keep the
    /// system's own contrast, which follows what is behind them like the status icons do;
    /// forcing a scheme until the title moved made a side toolbar (iPhone Duo) flip at a
    /// different scroll point than the status icons.
    func heroStatusBarBleed(enabled: Bool) -> some View {
        modifier(HeroStatusBarBleed(enabled: enabled))
    }
}

struct HeroStatusBarBleed: ViewModifier {
    let enabled: Bool

    @State private var statusBarHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.inlineTitleIsInNavigationBar) private var inlineTitleIsInNavigationBar

    /// Clear bar over the hero. Drops once the title has moved into the bar.
    private var keepsStatusBarClear: Bool {
        enabled && !inlineTitleIsInNavigationBar
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollEdgeEffectHidden(keepsStatusBarClear)
            .overlay(alignment: .top) {
                if keepsStatusBarClear, statusBarHeight > 0 {
                    StatusBarScrim(height: statusBarHeight * 2.4, reduceTransparency: reduceTransparency)
                }
            }
            .ignoresSafeArea(edges: enabled ? .top : [])
            .background {
                WindowTopInsetReader { top in
                    if top != statusBarHeight {
                        statusBarHeight = top
                    }
                }
                .frame(width: 0, height: 0)
            }
    }
}
