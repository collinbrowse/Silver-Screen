//
//  CardLabel.swift
//  SilverScreen
//
//  The label a surface card carries at its top ("STORYLINE", "AWARDS").
//

import SwiftUI

/// Small-capitals label inside a surface card, in the same style as the field labels
/// in the rating and facts cards. Cards label themselves this way; section titles
/// above content are kept for carousels and lists. VoiceOver reads `title` as a header.
struct CardLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(DesignTypography.factLabel)
            .foregroundStyle(DesignTheme.textMuted)
            .tracking(0.6)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}
