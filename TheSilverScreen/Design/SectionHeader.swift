//
//  SectionHeader.swift
//  TheSilverScreen
//

import SwiftUI

/// Section title with an optional trailing action (e.g. View All).
/// `onTitle` turns the title itself into the action — used only by the collection carousel.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onTitle: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center) {
            if let onTitle {
                Button(action: onTitle) {
                    HStack(spacing: DesignSpacing.xs) {
                        Text(title)
                            .font(DesignTypography.section)
                            .foregroundStyle(DesignTheme.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(DesignTypography.chip.weight(.semibold))
                            .foregroundStyle(DesignTheme.textSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isButton)
            } else {
                Text(title)
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: DesignSpacing.sm)
            if onTitle == nil, let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(DesignTypography.chip.weight(.semibold))
                        .foregroundStyle(DesignTheme.accent)
                        .padding(.horizontal, DesignSpacing.sm)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionTitle)
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
    }
}
