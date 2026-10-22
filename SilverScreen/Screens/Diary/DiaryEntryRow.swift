//
//  DiaryEntryRow.swift
//  SilverScreen
//
//  One diary row: the day, the poster, the title, and this watch's rating, rewatch
//  mark, review excerpt, and tags. Sizes come from `DiaryLayout`.
//

import SwiftUI

struct DiaryEntryRow: View {
    let row: DiaryRow
    let layout: DiaryLayout
    let imageLoader: ImageLoader

    @ScaledMetric(relativeTo: .title2) private var dayColumnWidth: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            VStack(spacing: 0) {
                Text(row.weekday.uppercased())
                    .font(DesignTypography.factLabel)
                    .foregroundStyle(DesignTheme.textMuted)
                Text(row.dayNumber)
                    .font(DesignTypography.ratingValue)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: dayColumnWidth)

            RemoteImageView(
                path: row.entry.posterPath,
                kind: .poster,
                width: layout.posterWidth,
                aspectRatio: 2 / 3,
                imageLoader: imageLoader,
                placeholderSystemImage: row.entry.subject.kind == .tv ? "tv" : "film",
                cornerRadius: DesignSpacing.sm
            )

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.xs) {
                    Text(row.title)
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                    if let year = row.yearText {
                        Text(year)
                            .font(DesignTypography.metadata)
                            .foregroundStyle(DesignTheme.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if row.ratingText != nil || row.isRewatch {
                    HStack(spacing: DesignSpacing.sm) {
                        if let rating = row.ratingText {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                Text(rating)
                            }
                            .font(DesignTypography.chip)
                            .foregroundStyle(DesignTheme.accent)
                        }
                        if row.isRewatch {
                            Label("Rewatch", systemImage: "arrow.counterclockwise")
                                .font(DesignTypography.chip)
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                    }
                }

                if let review = row.reviewExcerpt {
                    Text(review)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .lineLimit(layout.reviewLineLimit)
                }

                if let tags = row.tagsText {
                    Text(tags)
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
