//
//  DesignTokens.swift
//  TheSilverScreen
//
//  Shared visual language for SwiftUI screens.
//

import SwiftUI

enum DesignSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum DesignRadius {
    /// Continuous corner radius for posters, surface cards, and carousel media
    /// on new SwiftUI screens (iOS 26 / Apple TV–style squircle language).
    static let media: CGFloat = 22
    static let poster: CGFloat = media
    static let card: CGFloat = media
    static let carousel: CGFloat = media
    /// Fully rounded pills (genre chips).
    static let chip: CGFloat = 100
}

enum DesignTheme {
    /// Near-black in dark mode; system background in light.
    static var canvas: Color { Color(.systemBackground) }

    /// Card / chip surfaces.
    static var surface: Color { Color(.secondarySystemBackground) }

    static var textPrimary: Color { Color(.label) }
    static var textSecondary: Color { Color(.secondaryLabel) }
    static var textMuted: Color { Color(.tertiaryLabel) }
    static var separator: Color { Color(.separator) }

    /// Brand amber/orange for new screens — does not overwrite app AccentColor
    /// (Top Movies keeps system blue).
    static var accent: Color { Color("DesignAccent") }

    static var accentOnFill: Color { Color.black }
}

/// Bottom of the on-page title in the `detailScroll` coordinate space.
struct InlineTitleBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// True once `scrollingInlineTitle` has moved the on-page title into the bar.
/// Hero screens use this to retire the clear status-bar treatment.
private struct InlineTitleInNavigationBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inlineTitleIsInNavigationBar: Bool {
        get { self[InlineTitleInNavigationBarKey.self] }
        set { self[InlineTitleInNavigationBarKey.self] = newValue }
    }
}

/// Inline navigation title that appears only after the on-page title has scrolled away.
/// Rubber-banding past the top or bottom does not toggle it.
/// A hero screen passes `showsToolbarBackground: false` so the bar stays clear until that
/// title appears, then picks up the same blurred background as other screens.
struct ScrollingInlineTitle: ViewModifier {
    let title: String
    /// When false, the bar stays clear until the inline title is showing.
    var showsToolbarBackground: Bool = true
    @State private var showsTitle = false
    @State private var titleBottom: CGFloat = 0

    private var showsBackground: Bool {
        showsToolbarBackground || showsTitle
    }

    func body(content: Content) -> some View {
        content
            .environment(\.inlineTitleIsInNavigationBar, showsTitle)
            .navigationTitle(showsTitle && !title.isEmpty ? title : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(showsBackground ? .visible : .hidden, for: .navigationBar)
            .onPreferenceChange(InlineTitleBottomKey.self) { titleBottom = $0 }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                let maxOffset = max(0, geometry.contentSize.height - geometry.containerSize.height)
                if offset < 0 || geometry.contentOffset.y > maxOffset {
                    return showsTitle
                }
                guard titleBottom > 0 else { return false }
                return offset > titleBottom
            } action: { _, shouldShow in
                guard shouldShow != showsTitle else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    showsTitle = shouldShow
                }
            }
    }
}

extension View {
    func scrollingInlineTitle(_ title: String, showsToolbarBackground: Bool = true) -> some View {
        modifier(ScrollingInlineTitle(title: title, showsToolbarBackground: showsToolbarBackground))
    }

    /// Reports this view's bottom so the bar title waits until it has left the scroll view.
    func inlineTitleAnchor() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InlineTitleBottomKey.self,
                    value: proxy.frame(in: .named("detailScroll")).maxY
                )
            }
        }
    }

    /// Hides a separator that does not sit between two cells.
    /// The first row drops the line above it; the last row drops the line below it.
    @ViewBuilder
    func listRowSeparatorBetweenCells(isFirst: Bool, isLast: Bool) -> some View {
        if isFirst, isLast {
            listRowSeparator(.hidden)
        } else if isFirst {
            listRowSeparator(.hidden, edges: .top)
        } else if isLast {
            listRowSeparator(.hidden, edges: .bottom)
        } else {
            self
        }
    }

    /// Hides the section hairline at the start or end of a list.
    /// A section that meets another section keeps that shared edge.
    @ViewBuilder
    func listSectionSeparatorBetweenCells(isFirstSection: Bool, isLastSection: Bool) -> some View {
        if isFirstSection, isLastSection {
            listSectionSeparator(.hidden)
        } else if isFirstSection {
            listSectionSeparator(.hidden, edges: .top)
        } else if isLastSection {
            listSectionSeparator(.hidden, edges: .bottom)
        } else {
            self
        }
    }
}

enum DesignTypography {
    static var title: Font { .title2.bold() }
    static var section: Font { .headline }
    static var body: Font { .body }
    static var metadata: Font { .subheadline }
    static var factLabel: Font { .caption2.weight(.semibold) }
    static var factValue: Font { .title3.weight(.semibold) }
    static var chip: Font { .caption.weight(.medium) }
    static var ratingValue: Font { .title2.bold() }
}
