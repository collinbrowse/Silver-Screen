//
//  DiaryDayColumn.swift
//  SilverScreen
//
//  The weekday-over-day-number column at the leading edge of every diary row.
//

import SwiftUI

/// The poster a row on a show's history leads with. `path` is nil when neither the season
/// nor the series has one, and the row draws a placeholder so the columns stay aligned.
struct DiaryLeadingPoster: Equatable {
    let path: String?
}

struct DiaryDayColumn: View {
    /// "Thu"
    let weekday: String
    /// "16"
    let dayNumber: String

    @ScaledMetric(relativeTo: .title2) private var width: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            Text(weekday.uppercased())
                .font(DesignTypography.factLabel)
                .foregroundStyle(DesignTheme.textMuted)
            Text(dayNumber)
                .font(DesignTypography.ratingValue)
                .foregroundStyle(DesignTheme.textPrimary)
                .monospacedDigit()
        }
        .frame(width: width)
    }
}
