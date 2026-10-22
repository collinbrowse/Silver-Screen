//
//  OnboardingWelcomeView.swift
//  SilverScreen
//
//  First onboarding screen: the app icon and name, three promises, Get Started and Skip.
//

import SwiftUI

struct OnboardingWelcomeView: View {
    let onGetStarted: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xxl) {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    // The app icon artwork, so the brand mark matches the Home Screen.
                    Image("AppIconMark")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(DesignTheme.separator, lineWidth: 0.5)
                        }
                        .accessibilityHidden(true)
                    Text("Silver Screen")
                        .font(.largeTitle.bold())
                        .foregroundStyle(DesignTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, DesignSpacing.xxl)

                VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                    feature(
                        symbol: "star.leadinghalf.filled",
                        title: "Rate anything",
                        message: "Movies, shows, seasons, and single episodes, in half points out of 10."
                    )
                    feature(
                        symbol: "trophy",
                        title: "Awards built in",
                        message: "Oscar, BAFTA, and Emmy history on every title and person."
                    )
                    feature(
                        symbol: "lock",
                        title: "Private, with no account",
                        message: "Your library and ratings stay on this device."
                    )
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, DesignSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: DesignSpacing.sm) {
                Button(action: onGetStarted) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTheme.accent)
                .foregroundStyle(DesignTheme.accentOnFill)

                Button("Skip", action: onSkip)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Closes setup. You can start it again from the Library.")
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, DesignSpacing.xl)
            .padding(.vertical, DesignSpacing.md)
            .frame(maxWidth: .infinity)
            .background(DesignTheme.canvas)
        }
        .background(DesignTheme.canvas)
    }

    private func feature(symbol: String, title: String, message: String) -> some View {
        // Centered on the title and description together, not the title's baseline.
        HStack(alignment: .center, spacing: DesignSpacing.lg) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(DesignTheme.accent)
                .frame(minWidth: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(title)
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                Text(message)
                    .font(DesignTypography.body)
                    .foregroundStyle(DesignTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
