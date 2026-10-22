//
//  OnboardingRateChip.swift
//  SilverScreen
//
//  Under a picked poster: "Rate" until a score is saved, then the score. Tapping
//  it opens the same rating sheet as the detail screens.
//

import SwiftUI

struct OnboardingRateChip: View {
    let title: String
    let score: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                score.map { String(format: "%.1f", $0) } ?? "Rate",
                systemImage: score == nil ? "star" : "star.fill"
            )
            .font(DesignTypography.chip)
            .monospacedDigit()
            .foregroundStyle(score == nil ? DesignTheme.textPrimary : DesignTheme.accentOnFill)
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.xs + 2)
            .background(
                Capsule().fill(score == nil ? DesignTheme.surface : DesignTheme.accent)
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(score.map { UserScore.accessibilityLabel($0) } ?? "Rate \(title)")
        .accessibilityHint(score == nil ? "Opens the rating editor." : "Opens the rating editor to change it.")
    }
}
