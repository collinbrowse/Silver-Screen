//
//  DiaryEpisodeGroupRow.swift
//  SilverScreen
//
//  A diary row for a show's episodes checked off on one day: the day, the show's
//  poster and name, and which episodes. Sizes come from `DiaryLayout`.
//

import SwiftUI

struct DiaryEpisodeGroupRow: View {
    let group: DiaryEpisodeGroup
    let layout: DiaryLayout
    let imageLoader: ImageLoader
    /// False on the show's own history, where the poster and name repeat the screen's name.
    var showsTitle = true

    var body: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            DiaryDayColumn(weekday: group.weekday, dayNumber: group.dayNumber)

            if showsTitle {
                RemoteImageView(
                    path: group.posterPath,
                    kind: .poster,
                    width: layout.posterWidth,
                    aspectRatio: 2 / 3,
                    imageLoader: imageLoader,
                    placeholderSystemImage: "tv",
                    cornerRadius: DesignSpacing.sm
                )
            }

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                if showsTitle {
                    Text(group.seriesTitle)
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DiaryIconText(text: group.episodesText, systemImage: "tv")
                    .foregroundStyle(DesignTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignSpacing.xs)
        .contentShape(Rectangle())
        // Same divider start as `DiaryEntryRow`.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.accessibilityLabel)
    }
}
