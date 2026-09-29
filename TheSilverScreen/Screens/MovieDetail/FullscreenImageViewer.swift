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
