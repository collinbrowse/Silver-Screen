//
//  GenreShelfCard.swift
//  TheSilverScreen
//
//  Search-home genre card. Logo teal gradient on the label; the fill matches
//  the screen. Uppercase for display, title case for VoiceOver.
//

import SwiftUI

struct GenreShelfCard: View {
    let genre: MergedGenre

    var body: some View {
        Text(genre.title)
            .font(DesignTypography.section)
            .fontWeight(.semibold)
            .tracking(0.6)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .foregroundStyle(logoGradient)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 112)
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.sm)
            .background(DesignTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .strokeBorder(DesignTheme.separator.opacity(0.5), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(genre.title)
    }

    private var logoGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.361, green: 0.604, blue: 0.678),
                Color(red: 0.188, green: 0.365, blue: 0.427),
                Color(red: 0.831, green: 0.659, blue: 0.325),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
