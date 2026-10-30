//
//  TMDBRatingCard.swift
//  SilverScreen
//
//  Star card for a TMDB user score, with the viewer's own half-point score beside it.
//  A page can hide the viewer's side: an unwatched movie or episode has nothing to rate.
//

import SwiftUI

struct TMDBRatingCard: View {
    let formattedRating: String
    let accessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    /// Says where the score came from, e.g. "from your Oct 16 watch".
    var userScoreCaption: String? = nil
    var showsUserSide = true
    /// The prompt with no score yet: "Rate season" and "Rate show" on those pages.
    var addRatingTitle = "Add rating"
    let onEdit: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: DesignSpacing.md) {
                tmdbSide
                if showsUserSide {
                    Divider()
                        .frame(maxHeight: 44)
                    userSide
                }
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
                if let userScoreCaption {
                    Text(userScoreCaption)
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: "plus")
                    .font(DesignTypography.metadata.weight(.semibold))
                    .accessibilityHidden(true)
                Text(addRatingTitle)
                    .font(DesignTypography.metadata.weight(.semibold))
            }
            .foregroundStyle(DesignTheme.accent)
            .frame(minHeight: 44)
        }
    }
}
