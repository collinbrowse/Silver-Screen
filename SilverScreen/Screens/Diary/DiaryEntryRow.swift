//
//  DiaryEntryRow.swift
//  SilverScreen
//
//  One diary row: the day, the poster, the title, and this watch's rating, rewatch
//  mark, and review excerpt. Sizes come from `DiaryLayout`.
//

import SwiftUI

struct DiaryEntryRow: View {
    let row: DiaryRow
    let layout: DiaryLayout
    let imageLoader: ImageLoader
    /// False on one title's history, where every row would repeat the same poster and
    /// title as the screen's name.
    var showsTitle = true
    /// Set on a show's history: the season poster, drawn left of the date.
    var leadingPoster: DiaryLeadingPoster?

    var body: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            if let leadingPoster {
                RemoteImageView(
                    path: leadingPoster.path,
                    kind: .poster,
                    width: layout.posterWidth,
                    aspectRatio: 2 / 3,
                    imageLoader: imageLoader,
                    placeholderSystemImage: "tv",
                    cornerRadius: DesignSpacing.sm
                )
            }

            DiaryDayColumn(weekday: row.weekday, dayNumber: row.dayNumber)

            if showsTitle {
                RemoteImageView(
                    path: row.entry.posterPath,
                    kind: .poster,
                    width: layout.posterWidth,
                    aspectRatio: 2 / 3,
                    imageLoader: imageLoader,
                    placeholderSystemImage: row.entry.subject.kind == .tv ? "tv" : "film",
                    cornerRadius: DesignSpacing.sm
                )
            }

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                if showsTitle {
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
                }

                if row.ratingText != nil || row.isRewatch || row.episodeText != nil {
                    HStack(spacing: DesignSpacing.sm) {
                        // Which episode, for an episode rewatch; same mark as an episodes row.
                        if let episode = row.episodeText {
                            DiaryIconText(text: episode, systemImage: "tv")
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                        if let rating = row.ratingText {
                            DiaryIconText(text: rating, systemImage: "star.fill")
                                .foregroundStyle(DesignTheme.accent)
                        }
                        if row.isRewatch {
                            DiaryIconText(text: "Rewatch", systemImage: "arrow.counterclockwise")
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                    }
                } else if !showsTitle && row.reviewExcerpt == nil {
                    // Without the title, a bare unrated watch would leave the row empty.
                    Text("No rating")
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textMuted)
                }

                if let review = row.reviewExcerpt {
                    Text(review)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .lineLimit(layout.reviewLineLimit)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignSpacing.xs)
        .contentShape(Rectangle())
        // Every diary divider starts at the row's edge; by default it follows the first text, which differs row to row.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
