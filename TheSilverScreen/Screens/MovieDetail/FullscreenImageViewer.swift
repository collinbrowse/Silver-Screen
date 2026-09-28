//
//  FullscreenImageViewer.swift
//  TheSilverScreen
//

import SwiftUI
import UIKit

struct FullscreenImageViewer: View {
    let images: [MovieImage]
    let initialID: String
    let imageKind: FullscreenImages.Kind
    let imageLoader: ImageLoader
    let onDismiss: () -> Void

    @State private var selection: String?
    @State private var isZoomed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        images: [MovieImage],
        initialID: String,
        imageKind: FullscreenImages.Kind = .backdrop,
        imageLoader: ImageLoader,
        onDismiss: @escaping () -> Void
    ) {
        self.images = images
        self.initialID = initialID
        self.imageKind = imageKind
        self.imageLoader = imageLoader
        self.onDismiss = onDismiss
        _selection = State(initialValue: initialID)
    }

    private var currentIndex: Int {
        guard let selection else { return 0 }
        return images.firstIndex(where: { $0.id == selection }) ?? 0
    }

    var body: some View {
        ZStack {
            DesignTheme.canvas.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(images) { item in
                        FullscreenImagePage(
                            item: item,
                            imageKind: imageKind,
                            imageLoader: imageLoader,
                            isZoomed: $isZoomed,
                            onTapDismiss: {
                                guard !isZoomed else { return }
                                onDismiss()
                            }
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .scrollDisabled(isZoomed)
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.top, DesignSpacing.sm)

                Spacer()

                if images.count > 1 {
                    Text("\(currentIndex + 1) of \(images.count)")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, DesignSpacing.sm)
                        .background { chromeBackground }
                        .padding(.bottom, DesignSpacing.lg)
                        .accessibilityLabel("Image \(currentIndex + 1) of \(images.count)")
                }
            }
        }
        .onChange(of: selection) { _, _ in
            isZoomed = false
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard !isZoomed else { return }
                    let horizontal = abs(value.translation.width)
                    let vertical = value.translation.height
                    if vertical > 100, vertical > horizontal {
                        onDismiss()
                    }
                }
        )
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background { chromeBackground }
        }
        .accessibilityLabel("Close")
    }

    @ViewBuilder
    private var chromeBackground: some View {
        if reduceTransparency {
            Capsule()
                .fill(DesignTheme.surface)
        } else {
            Capsule()
                .glassEffect()
        }
    }
}

private struct FullscreenImagePage: View {
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

/// Pinch and drag zoom for one fullscreen image. At 1x the parent pager owns horizontal swipes.
private struct ZoomableImage: View {
    let image: UIImage
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnify)
            .simultaneousGesture(scale > 1 ? pan : nil)
            .onTapGesture(count: 2, perform: reset)
            .onTapGesture(count: 1) {
                guard scale <= 1 else { return }
                onSingleTap()
            }
            .onChange(of: isZoomed) { _, zoomed in
                if !zoomed {
                    scale = 1
                    settledScale = 1
                    offset = .zero
                    settledOffset = .zero
                }
            }
            .accessibilityLabel("Image")
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = min(4, max(1, settledScale * value.magnification))
                scale = next
                isZoomed = next > 1.01
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    reset()
                } else {
                    settledScale = scale
                    isZoomed = true
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                settledOffset = offset
            }
    }

    private func reset() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
        isZoomed = false
    }
}
