//
//  CatalogRowView.swift
//  SilverScreen
//
//  One row layout for movie, TV, and people catalog lists.
//

import SwiftUI

struct CatalogRowView: View {
    /// Standard browse/detail / Search View-all rows vs dense Search typeahead.
    enum Density: Sendable, Equatable {
        case standard
        /// Smaller poster and tighter type so many Search typeahead hits fit on one phone screen.
        case compact
    }

    let title: String
    /// Next up episode for tv series
    var nextUp: String? = nil
    let genre: String
    let metadata: String
    /// Personal score shown under the date. Not a control.
    var userScore: String? = nil
    /// Optional media kind chip shown last (full-screen Movie/TV lists and Search View all).
    var kindLabel: String? = nil
    var density: Density = .standard
    let imagePath: String?
    let imageKind: ImageLoader.ImageKind
    let placeholderSystemImage: String
    let imageLoader: ImageLoader

    private var imageWidth: CGFloat {
        switch density {
            case .standard: 120
            case .compact: 40
        }
    }

    var body: some View {
        HStack(alignment: density == .compact ? .center : .top, spacing: density == .compact ? DesignSpacing.sm : DesignSpacing.md) {
            RemoteImageView(
                path: imagePath,
                kind: imageKind,
                width: imageWidth,
                aspectRatio: imageKind == .profile || imageKind == .poster ? 2 / 3 : 16 / 9,
                imageLoader: imageLoader,
                placeholderSystemImage: placeholderSystemImage
            )
            VStack(alignment: .leading, spacing: density == .compact ? DesignSpacing.xs : DesignSpacing.sm) {
                Text(title)
                    .font(density == .compact ? DesignTypography.body : DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .lineLimit(density == .compact ? 1 : nil)
                    .fixedSize(horizontal: false, vertical: density != .compact)
                // Standard: Title → Next up → Genre → year → rating (kind chip last when present).
                if density == .standard, let nextUp {
                    Text(nextUp)
                        .font(DesignTypography.body)
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityLabel("Next episode, \(nextUp)")
                }
                if let userScore {
                    Text(userScore)
                        .font(density == .standard ? DesignTypography.body : DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityLabel("Your rating, \(userScore)")
                }
                if density == .standard, !genre.isEmpty {
                    Text(genre)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(density == .standard ? DesignTypography.metadata : DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .lineLimit(density == .compact ? 1 : nil)
                        .fixedSize(horizontal: false, vertical: density != .compact)
                }
                if let kindLabel, !kindLabel.isEmpty {
                    Text(kindLabel)
                        .font(DesignTypography.chip.weight(.semibold))
                        .foregroundStyle(DesignTheme.accentOnFill)
                        .padding(.horizontal, DesignSpacing.sm)
                        .padding(.vertical, 2)
                        .background(DesignTheme.accent, in: Capsule())
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            title,
            density == .standard ? (nextUp ?? "") : "",
            density == .standard ? genre : "",
            metadata,
            userScore ?? "",
            kindLabel ?? "",
        ]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
