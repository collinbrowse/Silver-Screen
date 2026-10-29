//
//  DiaryIconText.swift
//  SilverScreen
//
//  A small icon tight against its text, for the rating, rewatch, and episodes marks
//  in diary rows.
//

import SwiftUI

/// Icon and text two points apart. A `Label` in a `List` row puts its icon in a
/// fixed-width column, which leaves a wide gap before short text like "Rewatch".
struct DiaryIconText: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(DesignTypography.chip)
    }
}
