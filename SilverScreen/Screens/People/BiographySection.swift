//
//  BiographySection.swift
//  SilverScreen
//
//  Collapsed biography that expands in place via Show More / Show Less, in a card
//  that labels itself like the storyline on title pages.
//

import SwiftUI

struct BiographySection: View {
    let biography: String

    @State private var expanded = false

    private let previewLineLimit = 10
    /// Rough threshold where ~10 body lines are typically exceeded.
    private let expandsWhenCharacterCountExceeds = 500

    private var displayText: String {
        biography.isEmpty ? "No biography available." : biography
    }

    private var canExpand: Bool {
        !biography.isEmpty && biography.count > expandsWhenCharacterCountExceeds
    }

    /// A labeled card, like the storyline on title pages.
    var body: some View {
        SurfaceCard {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            CardLabel(title: "Biography")

            Text(displayText)
                .font(DesignTypography.body)
                .foregroundStyle(DesignTheme.textSecondary)
                .lineLimit(canExpand && !expanded ? previewLineLimit : nil)
                .fixedSize(horizontal: false, vertical: true)

            if canExpand {
                Button(expanded ? "Show Less" : "Show More") {
                    expanded.toggle()
                }
                .font(DesignTypography.chip.weight(.semibold))
                .foregroundStyle(DesignTheme.accent)
                .frame(minHeight: 44)
                .accessibilityHint(
                    expanded ? "Collapses the biography" : "Expands the full biography"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}
