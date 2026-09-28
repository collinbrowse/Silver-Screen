//
//  TagChip.swift
//  TheSilverScreen
//

import SwiftUI

/// Noninteractive pill label for genres and other metadata tags.
struct TagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DesignTypography.chip)
            .foregroundStyle(DesignTheme.textPrimary)
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.xs + 2)
            .background(DesignTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(DesignTheme.separator.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}
