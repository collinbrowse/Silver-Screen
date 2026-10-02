//
//  StreamingProviderLogoRow.swift
//  TheSilverScreen
//
//  Subscription service logos on a detail hero.
//

import SwiftUI
import UIKit

/// Provider logos for flatrate streaming. Icons scroll horizontally when they overflow.
struct StreamingProviderLogoRow: View {
    let providers: [StreamingProvider]
    let imageLoader: ImageLoader

    @Environment(\.openURL) private var openURL

    private let iconSize: CGFloat = 44

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSpacing.md) {
                ForEach(providers) { provider in
                    providerIcon(for: provider)
                }
            }
        }
        .frame(height: iconSize)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func providerIcon(for provider: StreamingProvider) -> some View {
        let icon = StreamingProviderAppIcon(
            path: provider.logoPath,
            imageLoader: imageLoader,
            size: iconSize
        )
        if StreamingProviderLaunch.destination(for: provider.id) != nil {
            Button {
                if let url = StreamingProviderLaunch.targetURL(for: provider) {
                    openURL(url)
                }
            } label: {
                icon
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                StreamingProviderLaunch.accessibilityLabel(
                    for: provider,
                    isAppInstalled: { url in UIApplication.shared.canOpenURL(url) }
                )
            )
        } else {
            icon
                .accessibilityLabel(provider.name)
        }
    }
}

/// JustWatch credit for watch-provider data, shown at the bottom of a detail scroll.
struct JustWatchAttributionFooter: View {
    var body: some View {
        Text("Streaming availability from JustWatch via TMDB")
            .font(DesignTypography.factLabel)
            .foregroundStyle(DesignTheme.textMuted)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Streaming availability data from JustWatch via TMDB")
    }
}

private struct StreamingProviderAppIcon: View {
    let path: String?
    let imageLoader: ImageLoader
    let size: CGFloat

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    /// Continuous corner radius matching the iOS home-screen icon proportion.
    private var cornerRadius: CGFloat {
        size * 0.2237
    }

    private var iconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// TMDB logos often include outer padding or a pre-masked icon; slight overscan fills our mask.
    private let artworkOverscan: CGFloat = 1.14

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .scaleEffect(artworkOverscan)
            } else {
                iconShape
                    .fill(DesignTheme.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(iconShape)
        .overlay {
            iconShape
                .strokeBorder(DesignTheme.separator.opacity(0.25), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .accessibilityHidden(true)
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        image = nil
        guard let path,
              let url = ImageLoader.imageURL(
                  path: path,
                  kind: .logo,
                  targetWidthPoints: size,
                  scale: displayScale
              ) else {
            return
        }
        let expected = path
        let loaded = try? await imageLoader.image(
            for: url,
            targetSize: CGSize(width: size, height: size),
            scale: displayScale
        )
        guard expected == path else { return }
        image = loaded
    }
}
