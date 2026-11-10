//
//  ShareCardSheet.swift
//  SilverScreen
//
//  Loads a card's posters, renders it once, and offers the image to the share sheet.
//  Rendering happens here rather than at the call site so a context-menu "Share" can
//  open instantly and fill in while posters arrive.
//

import SwiftUI

struct ShareCardSheet: View {
    let content: ShareCardContent
    let imageLoader: ImageLoader

    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSpacing.lg) {
                Group {
                    if let rendered {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
                            .accessibilityLabel(accessibilityText)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Preparing the image")
                    }
                }
                .frame(maxWidth: 360, maxHeight: 450)

                if let rendered {
                    ShareLink(
                        item: Image(uiImage: rendered),
                        preview: SharePreview(content.title, image: Image(uiImage: rendered))
                    ) {
                        Label("Share Image", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(DesignSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTheme.canvas)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: content.id) {
            rendered = await Self.render(content, imageLoader: imageLoader)
        }
    }

    private var accessibilityText: String {
        [content.title, content.subtitle, content.scoreText.map { "Rated \($0) out of 10" }, content.dateLine]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// Loads every poster the card needs (a failed one becomes a placeholder), then draws
    /// the card at 3x so the image is 1080 × 1350.
    static func render(_ content: ShareCardContent, imageLoader: ImageLoader) async -> UIImage? {
        let width = content.kind == .watch ? 120.0 : 96.0
        let scale = 3.0
        var posters: [String: UIImage] = [:]
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for path in content.posterPaths {
                guard
                    let url = ImageLoader.imageURL(path: path, kind: .poster, targetWidthPoints: width, scale: scale)
                else { continue }
                group.addTask {
                    let size = CGSize(width: width, height: width * 1.5)
                    return (path, await imageLoader.displayImage(for: url, targetSize: size, scale: scale))
                }
            }
            for await (path, image) in group {
                if let image {
                    posters[path] = image
                }
            }
        }
        guard !Task.isCancelled else { return nil }
        let renderer = ImageRenderer(content: ShareCardView(content: content, posters: posters))
        renderer.scale = scale
        return renderer.uiImage
    }
}
