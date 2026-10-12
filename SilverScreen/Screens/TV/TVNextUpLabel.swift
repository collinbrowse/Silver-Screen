//
//  TVNextUpLabel.swift
//  SilverScreen
//
//  In Progress “Next up” line on series and season detail, under the title and
//  above the hero metadata line (season · genre · year).
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
