//
//  LogWatchCardRow.swift
//  SilverScreen
//
//  One line of the "Log a watch" card on a detail screen.
//

import SwiftUI

/// One tappable line of the card: an icon, a title, an optional subtitle, and a chevron.
struct LogWatchCardRow: View {
    let systemImage: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(DesignTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(title)
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTheme.textMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
