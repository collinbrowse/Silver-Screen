//
//  OnboardingBottomBar.swift
//  SilverScreen
//
//  The full-width primary button pinned under each onboarding grid.
//

import SwiftUI

struct OnboardingBottomBar: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTheme.accent)
        .foregroundStyle(DesignTheme.accentOnFill)
        .frame(maxWidth: 560)
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
