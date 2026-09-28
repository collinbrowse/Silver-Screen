//
//  MoviePosterView.swift
//  TheSilverScreen
//

import SwiftUI
import UIKit

/// Shared 2:3 poster for new SwiftUI screens. Inject `ImageLoader`; do not fetch in the view.
struct MoviePosterView: View {
    let posterPath: String?
    let imageLoader: ImageLoader
    let width: CGFloat

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    DesignTheme.surface
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(DesignTheme.textMuted)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous))
        .accessibilityHidden(true)
        .task(id: posterPath) {
            await loadPoster()
        }
    }

    private func loadPoster() async {
        image = nil
        guard let posterPath,
              let url = ImageLoader.posterURL(
                path: posterPath,
                targetWidthPoints: width,
                scale: displayScale
              ) else {
            return
        }
        let expectedPath = posterPath
        let loaded = try? await imageLoader.image(
            for: url,
            targetSize: CGSize(width: width, height: height),
            scale: displayScale
        )
        guard expectedPath == posterPath else { return }
        image = loaded
    }
}
