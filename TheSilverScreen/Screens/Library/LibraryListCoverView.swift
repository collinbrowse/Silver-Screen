//
//  LibraryListCoverView.swift
//  TheSilverScreen
//
//  Square tile for a library row. System lists are an icon on a fill.
//  Custom lists collage up to four images the way a Spotify playlist cover does.
//

import SwiftUI

/// 64pt cover for one library list. Decorative; the row label is the name and count.
struct LibraryListCoverView: View {
    let artwork: LibraryListArtwork
    let segment: LibrarySegment
    let imageLoader: ImageLoader

    private let side: CGFloat = 64
    private let gutter: CGFloat = 2
    private let cornerRadius: CGFloat = 12

    var body: some View {
        content
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch artwork {
            case .watched:
                iconTile(
                systemImage: "eye.fill",
                foreground: DesignTheme.accent,
                background: DesignTheme.surface
                )
            case .watchlist:
                iconTile(
                systemImage: "bookmark.fill",
                foreground: DesignTheme.accent,
                background: DesignTheme.surface
                )
            case .images(let paths):
                collage(paths)
        }
    }

    /// One image fills the square. Two sit side by side. Three put the first
    /// image full height on the left and stack the other two. Four or more is a 2×2.
    @ViewBuilder
    private func collage(_ paths: [String]) -> some View {
        switch paths.count {
            case 0:
                iconTile(
                systemImage: placeholderSymbol,
                foreground: DesignTheme.textMuted,
                background: DesignTheme.surface
                )
            case 1:
                cell(paths[0], width: side, aspectRatio: 1)
            case 2:
                HStack(spacing: gutter) {
                cell(paths[0], width: half, aspectRatio: half / side)
                cell(paths[1], width: half, aspectRatio: half / side)
                }
            case 3:
                HStack(spacing: gutter) {
                cell(paths[0], width: half, aspectRatio: half / side)
                VStack(spacing: gutter) {
                    cell(paths[1], width: half, aspectRatio: 1)
                    cell(paths[2], width: half, aspectRatio: 1)
                }
                }
            default:
                let four = Array(paths.prefix(4))
                VStack(spacing: gutter) {
                HStack(spacing: gutter) {
                    cell(four[0], width: half, aspectRatio: 1)
                    cell(four[1], width: half, aspectRatio: 1)
                }
                HStack(spacing: gutter) {
                    cell(four[2], width: half, aspectRatio: 1)
                    cell(four[3], width: half, aspectRatio: 1)
                }
                }
        }
    }

    private var half: CGFloat { (side - gutter) / 2 }

    private var placeholderSymbol: String {
        segment == .people ? "person" : "film"
    }

    private var imageKind: ImageLoader.ImageKind {
        segment == .people ? .profile : .poster
    }

    private func iconTile(systemImage: String, foreground: Color, background: Color) -> some View {
        ZStack {
            background
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(foreground)
        }
    }

    private func cell(_ path: String, width: CGFloat, aspectRatio: CGFloat) -> some View {
        RemoteImageView(
            path: path,
            kind: imageKind,
            width: width,
            aspectRatio: aspectRatio,
            imageLoader: imageLoader,
            placeholderSystemImage: placeholderSymbol,
            cornerRadius: 0
        )
    }
}
