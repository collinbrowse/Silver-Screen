//
//  DetailCarousel.swift
//  TheSilverScreen
//

import SwiftUI

/// Apple TV–style horizontal carousel: section title, peek of the next card, continuous corners.
struct DetailCarousel<Content: View>: View {
    let title: String
    var viewAllTitle: String? = nil
    var onViewAll: (() -> Void)? = nil
    var onTitle: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        viewAllTitle: String? = nil,
        onViewAll: (() -> Void)? = nil,
        onTitle: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.viewAllTitle = viewAllTitle
        self.onViewAll = onViewAll
        self.onTitle = onTitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            SectionHeader(
                title: title,
                actionTitle: viewAllTitle,
                action: onViewAll,
                onTitle: onTitle
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DesignSpacing.md) {
                    content()
                }
                .scrollTargetLayout()
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.vertical, DesignSpacing.xs)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .scrollEdgeEffectHidden(true)
        }
    }
}

struct CarouselCardFrame: ViewModifier {
    let width: CGFloat
    let aspectRatio: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: width / aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.carousel, style: .continuous))
    }
}

extension View {
    func carouselCard(width: CGFloat, aspectRatio: CGFloat) -> some View {
        modifier(CarouselCardFrame(width: width, aspectRatio: aspectRatio))
    }
}
