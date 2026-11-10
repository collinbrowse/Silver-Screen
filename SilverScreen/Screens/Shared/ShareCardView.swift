//
//  ShareCardView.swift
//  SilverScreen
//
//  The image people share: a fixed 4:5 card (1080 × 1350 at 3x) that reads well in
//  stories and messages. Always dark, so it looks the same whatever the sharer's
//  appearance setting, and drawn from already-loaded posters because `ImageRenderer`
//  does not wait for async images.
//

import SwiftUI

struct ShareCardView: View {
    let content: ShareCardContent
    /// Loaded posters by path. A missing path draws a placeholder.
    let posters: [String: UIImage]

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            switch content.kind {
                case .watch:
                    watchBody
                case .list:
                    listBody
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(DesignSpacing.xl)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private var watchBody: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack(alignment: .top, spacing: DesignSpacing.lg) {
                poster(content.posterPaths.first, width: 120)
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    heading
                    if let score = content.scoreText {
                        Label(score, systemImage: "star.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(DesignTheme.accent)
                            .padding(.top, DesignSpacing.xs)
                    }
                    if let date = content.dateLine {
                        Text(date)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            if let review = content.reviewExcerpt {
                Text(review)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(9)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var listBody: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            heading
            let columns = Array(repeating: GridItem(.flexible(), spacing: DesignSpacing.sm), count: 3)
            LazyVGrid(columns: columns, spacing: DesignSpacing.sm) {
                ForEach(Array(content.posterPaths.enumerated()), id: \.offset) { _, path in
                    poster(path, width: 96)
                }
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DesignSpacing.xs) {
            Image(systemName: "film.stack")
            Text("Silver Screen")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.6))
    }

    private func poster(_ path: String?, width: CGFloat) -> some View {
        let image = path.flatMap { posters[$0] }
        return ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: content.kind == .list ? "film" : "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: DesignSpacing.sm, style: .continuous))
    }
}
