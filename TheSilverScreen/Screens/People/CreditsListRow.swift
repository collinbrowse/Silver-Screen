//
//  CreditsListRow.swift
//  TheSilverScreen
//

import SwiftUI

struct CreditsListRow: View {
    let item: CreditsListItem
    let imageLoader: ImageLoader

    private let posterWidth: CGFloat = 70
    private let posterAspect: CGFloat = 2 / 3

    var body: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            RemoteImageView(
                path: item.credit.posterPath,
                kind: .poster,
                width: posterWidth,
                aspectRatio: posterAspect,
                imageLoader: imageLoader,
                placeholderSystemImage: item.credit.mediaType == .tv ? "tv" : "film"
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous))

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(item.credit.title)
                    .font(DesignTypography.metadata.weight(.semibold))
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.genreNames.isEmpty {
                    Text(item.genreNames.joined(separator: ", "))
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.formattedReleaseDate)
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [item.credit.title]
        if !item.genreNames.isEmpty {
            parts.append(item.genreNames.joined(separator: ", "))
        }
        if item.formattedReleaseDate != "Not available" {
            parts.append(item.formattedReleaseDate)
        }
        switch item.credit.mediaType {
            case .movie: parts.append("Movie")
            case .tv: parts.append("TV series")
        }
        return parts.joined(separator: ", ")
    }
}
