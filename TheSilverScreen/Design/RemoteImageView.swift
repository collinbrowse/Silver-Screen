//
//  RemoteImageView.swift
//  TheSilverScreen
//

import SwiftUI
import UIKit

/// Shared remote image. Inject `ImageLoader`; do not fetch in the view.
struct RemoteImageView: View {
    let path: String?
    let kind: ImageLoader.ImageKind
    let width: CGFloat
    let aspectRatio: CGFloat
    let imageLoader: ImageLoader
    var placeholderSystemImage: String = "photo"
    /// Continuous corner radius. Pass `0` when the image should run edge to edge.
    var cornerRadius: CGFloat = DesignRadius.media

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    private var height: CGFloat { width / aspectRatio }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    DesignTheme.surface
                    Image(systemName: placeholderSystemImage)
                        .font(.title2)
                        .foregroundStyle(DesignTheme.textMuted)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
                kind: kind,
                targetWidthPoints: width,
                scale: displayScale
              ) else {
            return
        }
        let expected = path
        let loaded = try? await imageLoader.image(
            for: url,
            targetSize: CGSize(width: width, height: height),
            scale: displayScale
        )
        guard expected == path else { return }
        image = loaded
    }
}
