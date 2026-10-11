//
//  ExpandableTextToggle.swift
//  TheSilverScreen
//
//  Shared Show More / Show Less for review-style bodies. Truncation is measured
//  against a 6-line collapse so Dynamic Type still gets a toggle when needed.
//

import SwiftUI

/// Body text that collapses to six lines with the same Show More control as reviews.
struct ExpandableTextToggle: View {
    let text: String
    var scrollTo: (String) -> Void = { _ in }
    var scrollID: String? = nil
    /// When set, taps on the body (not Show More) invoke this — used by Your review.
    var onTextTap: (() -> Void)? = nil

    @State private var expanded = false
    @State private var isTruncated = false
    @State private var topOffset: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var limitedHeight: CGFloat = 0

    private static let collapsedLineLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Group {
                if let onTextTap {
                    Button(action: onTextTap) {
                        bodyText
                    }
                    .buttonStyle(.plain)
                } else {
                    bodyText
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .named("detailScroll")).minY, initial: true) { _, minY in
                            topOffset = minY
                        }
                }
            }

            if isTruncated || expanded {
                Button(expanded ? "Show Less" : "Show More") {
                    toggleExpanded()
                }
                .font(DesignTypography.chip.weight(.semibold))
                .foregroundStyle(DesignTheme.accent)
            }
        }
        .onChange(of: text) { _, _ in
            expanded = false
            isTruncated = false
            fullHeight = 0
            limitedHeight = 0
        }
        .animation(.smooth(duration: 0.35), value: expanded)
    }

    private var bodyText: some View {
        Text(text)
            .font(DesignTypography.body)
            .foregroundStyle(DesignTheme.textSecondary)
            .lineLimit(expanded ? nil : Self.collapsedLineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background { heightProbes }
    }

    /// Invisible full-height and 6-line copies used only to decide whether text is clipped.
    private var heightProbes: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(DesignTypography.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .overlay {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { updateFull(geo.size.height) }
                            .onChange(of: geo.size.height) { _, height in
                                updateFull(height)
                            }
                    }
                }

            Text(text)
                .font(DesignTypography.body)
                .lineLimit(Self.collapsedLineLimit)
                .hidden()
                .overlay {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { updateLimited(geo.size.height) }
                            .onChange(of: geo.size.height) { _, height in
                                updateLimited(height)
                            }
                    }
                }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func updateFull(_ height: CGFloat) {
        fullHeight = height
        refreshTruncation()
    }

    private func updateLimited(_ height: CGFloat) {
        limitedHeight = height
        refreshTruncation()
    }

    private func refreshTruncation() {
        guard fullHeight > 0, limitedHeight > 0 else { return }
        isTruncated = fullHeight > limitedHeight + 1
    }

    /// Grow and shrink in one motion. If the open card starts above the screen,
    /// keep that card on screen so the collapse does not snap the scroll offset.
    private func toggleExpanded() {
        withAnimation(.smooth(duration: 0.35)) {
            if expanded, topOffset < 0, let scrollID {
                scrollTo(scrollID)
            }
            expanded.toggle()
        }
    }
}
