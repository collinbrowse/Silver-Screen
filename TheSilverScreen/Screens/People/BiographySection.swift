//
//  BiographySection.swift
//  TheSilverScreen
//
//  Collapsed biography that expands in place via Show More / Show Less.
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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("Biography")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

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
