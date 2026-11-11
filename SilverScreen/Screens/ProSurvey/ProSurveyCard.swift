//
//  ProSurveyCard.swift
//  SilverScreen
//
//  The one-time Library card that invites someone to the Pro survey. Shown from
//  the second day the app is opened, until it is dismissed or answered
//  (`ProSurveyPrompt`).
//

import SwiftUI

struct ProSurveyCard: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: DesignSpacing.md) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(DesignTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("Pro is coming soon")
                        .font(.headline)
                        .foregroundStyle(DesignTheme.textPrimary)
                    Text("What features would you like to see?")
                        .font(.subheadline)
                        .foregroundStyle(DesignTheme.textSecondary)
                    Button("Pick Features", action: onOpen)
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTheme.accent)
                        .foregroundStyle(DesignTheme.accentOnFill)
                        .padding(.top, DesignSpacing.xs)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Pro survey")
            }
        }
    }
}
