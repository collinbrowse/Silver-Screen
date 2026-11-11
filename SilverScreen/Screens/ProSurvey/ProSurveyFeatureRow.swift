//
//  ProSurveyFeatureRow.swift
//  SilverScreen
//
//  One pickable feature: icon, name, one line of detail, and a checkmark.
//  VoiceOver reads it as one button with a Selected trait.
//

import SwiftUI

struct ProSurveyFeatureRow: View {
    let feature: ProFeature
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignSpacing.md) {
                Image(systemName: feature.systemImage)
                    .font(.body)
                    .foregroundStyle(DesignTheme.accent)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text(feature.title)
                        .font(.body)
                        .foregroundStyle(DesignTheme.textPrimary)
                    Text(feature.detail)
                        .font(.subheadline)
                        .foregroundStyle(DesignTheme.textSecondary)
                }
                Spacer(minLength: DesignSpacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DesignTheme.accent : DesignTheme.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Removes this pick" : "Adds this pick")
    }
}
