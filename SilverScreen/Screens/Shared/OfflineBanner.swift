//
//  OfflineBanner.swift
//  SilverScreen
//
//  A thin strip under the status bar while the device has no network. The library,
//  diary, and lists are on device, so the banner says what still works.
//

import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        Label("You're offline. Your library still works.", systemImage: "wifi.slash")
            .font(DesignTypography.chip)
            .foregroundStyle(.primary)
            .padding(.vertical, DesignSpacing.xs)
            .padding(.horizontal, DesignSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Shows `OfflineBanner` above the content while `NetworkMonitor` reports no network.
/// A no-op where no monitor is in the environment (previews, tests).
struct OfflineBannerModifier: ViewModifier {
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    func body(content: Content) -> some View {
        let offline = network.map { !$0.isOnline } ?? false
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if offline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: offline)
    }
}

extension View {
    /// Adds the offline strip; see `OfflineBannerModifier`.
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
