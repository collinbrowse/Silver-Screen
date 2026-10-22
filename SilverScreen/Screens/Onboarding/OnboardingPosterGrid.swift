//
//  OnboardingPosterGrid.swift
//  SilverScreen
//
//  The poster grid both onboarding steps share. Columns come from the width the
//  grid is given, never from the device, so the same layout works on a phone,
//  an unfolded phone, and an iPad.
//

import SwiftUI

struct OnboardingPosterGrid<Cell: View>: View {
    let state: LoadState<[OnboardingTitle]>
    let emptyTitle: String
    let emptyMessage: String
    let retry: () async -> Void
    /// Builds one cell at the poster width the grid chose.
    @ViewBuilder let cell: (OnboardingTitle, CGFloat) -> Cell

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    private let spacing = DesignSpacing.md

    /// Larger text gets wider posters so titles and stars still fit.
    private var minimumPosterWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 150 : 104
    }

    private var layout: (columns: Int, width: CGFloat) {
        Self.layout(
            availableWidth: availableWidth,
            minimumPosterWidth: minimumPosterWidth,
            spacing: spacing
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .accessibilityLabel("Loading titles")
            case .empty:
                EmptyStateView(title: emptyTitle, message: emptyMessage, systemImage: "film.stack")
                    .frame(minHeight: 240)
            case .loaded(let titles, _):
                let layout = layout
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(layout.width), spacing: spacing, alignment: .top),
                        count: layout.columns
                    ),
                    alignment: .leading,
                    spacing: DesignSpacing.lg
                ) {
                    ForEach(titles) { title in
                        cell(title, layout.width)
                    }
                }
            case .failed(let error):
                ErrorStateView(error: error, retry: retry)
                    .frame(minHeight: 240)
        }
    }

    /// As many columns as fit at the minimum width, at least two, sharing the row evenly.
    static func layout(
        availableWidth: CGFloat,
        minimumPosterWidth: CGFloat,
        spacing: CGFloat
    ) -> (columns: Int, width: CGFloat) {
        guard availableWidth > 0 else { return (2, minimumPosterWidth) }
        let fitting = Int((availableWidth + spacing) / (minimumPosterWidth + spacing))
        let columns = max(fitting, 2)
        let width = (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return (columns, max(width.rounded(.down), 1))
    }
}
