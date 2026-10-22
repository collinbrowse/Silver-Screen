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

    /// A labeled card, like the storyline on title pages, with Show More below it.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    CardLabel(title: "Biography")

                    Text(displayText)
                        .font(DesignTypography.body)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .lineLimit(canExpand && !expanded ? previewLineLimit : nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if canExpand {
                // The whole row under the card is the button, as with the awards card.
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Show Less" : "Show More")
                        .font(DesignTypography.chip.weight(.semibold))
                        .foregroundStyle(DesignTheme.accent)
                        // Lines up with where the card's corner starts to round, not its outer edge.
                        .padding(.leading, DesignRadius.card)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    expanded ? "Collapses the biography" : "Expands the full biography"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}
