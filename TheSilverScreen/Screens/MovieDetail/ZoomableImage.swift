//
//  ZoomableImage.swift
//  TheSilverScreen
//
//  Pinch and drag zoom for one fullscreen image. At 1x the parent pager owns horizontal swipes.
//

import SwiftUI
import UIKit

struct ZoomableImage: View {
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
