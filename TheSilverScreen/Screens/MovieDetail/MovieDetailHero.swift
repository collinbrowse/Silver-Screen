//
//  MovieDetailHero.swift
//  TheSilverScreen
//
//  Shared detail header for movies, series, seasons, and episodes: a full-width
//  backdrop under the status icons, with the poster overlapping it when there is one.
//

import SwiftUI
import UIKit

/// Which backdrop stays on the hero when the image list or the user's page changes.
enum MovieHeroSelection {
    /// Keeps the backdrop the user is viewing. Falls back to the first image
    /// when that path is missing, and to `nil` when there is no artwork.
    static func backdropID(selected: String?, images: [MovieImage]) -> String? {
        if let selected, images.contains(where: { $0.id == selected }) {
            return selected
        }
        return images.first?.id
    }
}

/// Full-width backdrop stage. A poster overlaps the bottom when `posterPath` is set.
struct DetailHero<Metadata: View>: View {
    let title: String
    var eyebrow: String? = nil
    let posterPath: String?
    let images: [MovieImage]
    @Binding var selectedImageID: String?
    let imageLoader: ImageLoader
    let transitionNamespace: Namespace.ID
    let onOpenPoster: () -> Void
    let onOpenImage: (String) -> Void
    /// Genre names across the full width under the poster. Trailers stay in `metadata`, under the title.
    var genreNames: [String] = []
    @ViewBuilder let metadata: () -> Metadata

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Poster is larger than the old 112pt thumbnail so it reads as the title image.
    private var posterWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 128 : 156
    }

    /// How far the poster climbs into the backdrop. Episodes have no poster, so they sit below the still.
    private var posterOverlap: CGFloat {
        guard hasPoster, !images.isEmpty else { return 0 }
        return dynamicTypeSize.isAccessibilitySize ? 36 : 72
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !images.isEmpty {
                backdropStage
            }
            identity
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.top, hasPoster && !images.isEmpty ? DesignSpacing.sm : 0)
            if !genreNames.isEmpty {
                GenreChipRow(names: genreNames)
                    .padding(.horizontal, DesignSpacing.lg)
                    .padding(.top, DesignSpacing.md)
            }
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: images.map(\.id)) { _, _ in
            reconcileSelection()
        }
    }

    private var backdropStage: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = width * 9 / 16
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        backdropPage(image, index: index, width: width, height: height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedImageID)
            .scrollDisabled(images.count < 2)
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: DesignTheme.canvas.opacity(0.2), location: 0.45),
                        .init(color: DesignTheme.canvas, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * 0.42)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                pageCapsule
                    .padding(.trailing, DesignSpacing.lg)
                    .padding(.bottom, posterOverlap + DesignSpacing.md)
            }
            .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    private func backdropPage(_ image: MovieImage, index: Int, width: CGFloat, height: CGFloat) -> some View {
        RemoteImageView(
            path: image.filePath,
            kind: .backdrop,
            width: width,
            aspectRatio: 16.0 / 9.0,
            imageLoader: imageLoader,
            placeholderSystemImage: "photo",
            cornerRadius: 0
        )
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture { onOpenImage(image.id) }
        .matchedTransitionSource(id: image.id, in: transitionNamespace)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image \(index + 1) of \(images.count)")
        .accessibilityHint("Shows this image full screen")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var pageCapsule: some View {
        if images.count > 1, let index = currentIndex {
            Text("\(index + 1) of \(images.count)")
                .font(DesignTypography.metadata)
                .foregroundStyle(DesignTheme.textPrimary)
                .padding(.horizontal, DesignSpacing.md)
                .padding(.vertical, DesignSpacing.sm)
                .background { chromeBackground }
                .accessibilityHidden(true)
        }
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

    private var currentIndex: Int? {
        let id = MovieHeroSelection.backdropID(selected: selectedImageID, images: images)
        return images.firstIndex { $0.id == id }
    }

    @ViewBuilder
    private var identity: some View {
        if hasPoster {
            let poster = posterThumbnail
                .padding(.bottom, -posterOverlap)
                .offset(y: -posterOverlap)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    poster
                    titleColumn
                }
            } else {
                HStack(alignment: .top, spacing: DesignSpacing.md) {
                    poster
                    titleColumn
                }
            }
        } else {
            titleColumn
                .padding(.top, images.isEmpty ? 0 : DesignSpacing.md)
        }
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            titleText
            metadata()
        }
        .padding(.top, hasPoster ? DesignSpacing.xs : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(title)
            .font(DesignTypography.title)
            .foregroundStyle(DesignTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .inlineTitleAnchor()
            .accessibilityLabel(title)
            .accessibilityHint(hasPoster ? "Shows the poster full screen" : "")
            .accessibilityAddTraits(hasPoster ? .isButton : [])
            .accessibilityAction(named: "Show poster") {
                onOpenPoster()
            }
    }

    @ViewBuilder
    private var posterThumbnail: some View {
        let poster = MoviePosterView(
            posterPath: posterPath,
            imageLoader: imageLoader,
            width: posterWidth
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        if hasPoster, let posterPath {
            poster
                .contentShape(RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous))
                .matchedTransitionSource(id: posterPath, in: transitionNamespace)
                .onTapGesture(perform: onOpenPoster)
                .accessibilityAddTraits(.isButton)
        } else {
            poster
        }
    }

    private var hasPoster: Bool {
        guard let posterPath else { return false }
        return !posterPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reconcileSelection() {
        selectedImageID = MovieHeroSelection.backdropID(selected: selectedImageID, images: images)
    }
}

extension View {
    /// Draws the backdrop under the status icons, with a short fade that is darker at the top.
    /// The fade and the dark status-bar treatment lift once the inline title has moved into the bar.
    func heroStatusBarBleed(enabled: Bool) -> some View {
        modifier(HeroStatusBarBleed(enabled: enabled))
    }
}

private struct HeroStatusBarBleed: ViewModifier {
    let enabled: Bool

    @State private var statusBarHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.inlineTitleIsInNavigationBar) private var inlineTitleIsInNavigationBar

    /// Clear bar over the hero. Drops once the title has moved into the bar.
    private var keepsStatusBarClear: Bool {
        enabled && !inlineTitleIsInNavigationBar
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollEdgeEffectHidden(keepsStatusBarClear)
            .overlay(alignment: .top) {
                if keepsStatusBarClear, statusBarHeight > 0 {
                    StatusBarScrim(height: statusBarHeight * 2.4, reduceTransparency: reduceTransparency)
                }
            }
            .ignoresSafeArea(edges: enabled ? .top : [])
            .toolbarColorScheme(keepsStatusBarClear ? .dark : nil, for: .navigationBar)
            .background {
                WindowTopInsetReader { top in
                    if top != statusBarHeight {
                        statusBarHeight = top
                    }
                }
                .frame(width: 0, height: 0)
            }
    }
}

/// Soft shade under the time and status icons. Darkest at the screen edge, gone before the artwork.
private struct StatusBarScrim: View {
    let height: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(reduceTransparency ? 0.42 : 0.28), location: 0),
                .init(color: Color.black.opacity(reduceTransparency ? 0.16 : 0.08), location: 0.38),
                .init(color: Color.black.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Reports the window top inset, which is the band behind the clock and status icons.
private struct WindowTopInsetReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        func report() {
            let top = window?.safeAreaInsets.top ?? 0
            guard top > 0 else { return }
            onChange?(top)
        }
    }
}
