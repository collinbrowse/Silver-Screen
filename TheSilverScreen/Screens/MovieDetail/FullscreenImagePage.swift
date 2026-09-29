//
//  FullscreenImagePage.swift
//  TheSilverScreen
//

import SwiftUI
import UIKit

struct FullscreenImagePage: View {
    let item: MovieImage
    let imageKind: FullscreenImages.Kind
    let imageLoader: ImageLoader
    @Binding var isZoomed: Bool
    let onTapDismiss: () -> Void

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    private var loaderKind: ImageLoader.ImageKind {
        switch imageKind {
            case .poster: return .poster
            case .backdrop: return .backdrop
            case .profile: return .profile
        }
    }

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image, isZoomed: $isZoomed, onSingleTap: onTapDismiss)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTapDismiss)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            await load()
        }
    }

    private func load() async {
        image = nil
        let targetWidth: CGFloat
        let aspect: CGFloat
        switch imageKind {
            case .poster, .profile:
                targetWidth = 780
                aspect = 2 / 3
            case .backdrop:
                targetWidth = 1280
                aspect = 9 / 16
        }
        guard let url = ImageLoader.imageURL(
            path: item.filePath,
            kind: loaderKind,
            targetWidthPoints: targetWidth,
            scale: displayScale
        ) else { return }
        let expected = item.filePath
        let loaded = try? await imageLoader.image(
            for: url,
            targetSize: CGSize(width: targetWidth, height: targetWidth * aspect),
            scale: displayScale
        )
        guard expected == item.filePath else { return }
        image = loaded
    }
}
