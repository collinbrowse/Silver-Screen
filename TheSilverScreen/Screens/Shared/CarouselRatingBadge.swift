//
//  CarouselRatingBadge.swift
//  TheSilverScreen
//
//  Top-trailing status on a carousel poster: nothing → watched eye → personal
//  rating (rating wins when both apply).
//

import SwiftUI

struct CarouselRatingBadge: View {
    let formattedScore: String?
    var isWatched: Bool = false

    var body: some View {
        if let formattedScore, !formattedScore.isEmpty {
            Text(formattedScore)
                .font(DesignTypography.chip.weight(.semibold))
                .foregroundStyle(DesignTheme.accent)
                .padding(.horizontal, DesignSpacing.sm)
                .padding(.vertical, DesignSpacing.xs)
                .background(Color.black.opacity(0.55), in: Capsule())
                .accessibilityLabel("Your rating, \(formattedScore)")
        } else if isWatched {
            Image(systemName: "eye.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTheme.accent)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.55), in: Circle())
                .accessibilityLabel("Watched")
        }
    }
}
