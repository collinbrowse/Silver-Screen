//
//  OnboardingPosterCell.swift
//  SilverScreen
//
//  One tappable poster in an onboarding grid. A pick shows a checkmark badge and
//  an accent ring, and VoiceOver hears the pick in the value and selected trait.
//

import SwiftUI

struct OnboardingPosterCell<Accessory: View>: View {
    let title: OnboardingTitle
    let width: CGFloat
    let isPicked: Bool
    /// "Seen" or "On Watchlist", spoken as the value when picked.
    let pickedState: String
    let unpickedState: String
    let actionHint: String
    let imageLoader: ImageLoader
    let onTap: () -> Void
    /// Shown under the title, such as the inline stars.
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    MoviePosterView(
                        posterPath: title.draft.imagePath,
                        imageLoader: imageLoader,
                        width: width
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous)
                            .strokeBorder(DesignTheme.accent, lineWidth: isPicked ? 3 : 0)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPicked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(DesignTheme.accentOnFill, DesignTheme.accent)
                                .padding(DesignSpacing.sm)
                        }
                    }
                    Text(title.draft.title)
                        .font(.caption)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .frame(width: width, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title.accessibilityName)
            .accessibilityValue(isPicked ? pickedState : unpickedState)
            .accessibilityHint(actionHint)
            .accessibilityAddTraits(isPicked ? .isSelected : [])

            accessory()
                .frame(width: width)
        }
    }
}
