//
//  FullscreenImageViewer.swift
//  SilverScreen
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

    /// The page count and Close share a bottom toolbar (count leading, Close trailing),
    /// within thumb reach and off the top of the image. As toolbar items, the system
    /// places them for each screen, including the iPhone Duo's outer screen.
    var body: some View {
        NavigationStack {
            viewer
                .toolbar {
                    if images.count > 1 {
                        ToolbarItem(placement: .bottomBar) {
                            Text("\(currentIndex + 1) of \(images.count)")
                                .font(DesignTypography.metadata)
                                .foregroundStyle(DesignTheme.textPrimary)
                                .padding(.horizontal, DesignSpacing.sm)
                                .accessibilityLabel("Image \(currentIndex + 1) of \(images.count)")
                        }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button("Close", systemImage: "xmark", action: onDismiss)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .bottomBar)
        }
    }

    private var viewer: some View {
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
}
