//
//  TMDBRatingCard.swift
//  TheSilverScreen
//
//  Star card for a TMDB user score, with the viewer's own half-point score beside it.
//

import SwiftUI

struct TMDBRatingCard: View {
    let formattedRating: String
    let accessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let onEdit: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: DesignSpacing.md) {
                tmdbSide
                Divider()
                    .frame(maxHeight: 44)
                userSide
            }
        }
    }

    private var tmdbSide: some View {
        HStack(spacing: DesignSpacing.md) {
            Image(systemName: "star.fill")
                .foregroundStyle(DesignTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(formattedRating)
                    .font(DesignTypography.ratingValue)
                    .foregroundStyle(DesignTheme.textPrimary)
                Text("TMDB RATING")
                    .font(DesignTypography.factLabel)
                    .foregroundStyle(DesignTheme.textMuted)
                    .tracking(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var userSide: some View {
        Button(action: onEdit) {
            HStack {
                userLabel
                    .contentShape(Rectangle())
                if formattedUserScore != nil {
                    Image(systemName: "pencil")
                        .font(.system(size: 18).weight(.bold))
                        .foregroundStyle(DesignTheme.textPrimary)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .accessibilityLabel(userScoreAccessibilityLabel)
    }

    @ViewBuilder
    private var userLabel: some View {
        if let formattedUserScore {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(formattedUserScore)
                    .font(DesignTypography.ratingValue)
                    .foregroundStyle(DesignTheme.accent)
                Text("YOUR RATING")
                    .font(DesignTypography.factLabel)
                    .foregroundStyle(DesignTheme.textMuted)
                    .tracking(0.6)
            }
        } else {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: "plus")
                    .font(DesignTypography.metadata.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Add rating")
                    .font(DesignTypography.metadata.weight(.semibold))
            }
            .foregroundStyle(DesignTheme.accent)
            .frame(minHeight: 44)
        }
    }
}
