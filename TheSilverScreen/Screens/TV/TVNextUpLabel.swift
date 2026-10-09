//
//  TVNextUpLabel.swift
//  TheSilverScreen
//
//  In Progress “Next up” line on series and season detail, between streaming
//  providers (in the hero) and the rating card.
//

import SwiftUI

struct TVNextUpLabel: View {
    let subtitle: String

    var body: some View {
        Text(subtitle)
            .font(DesignTypography.metadata.weight(.semibold))
            .foregroundStyle(DesignTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(subtitle)
    }
}
