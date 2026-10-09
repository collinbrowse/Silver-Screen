//
//  SearchViewAllRow.swift
//  TheSilverScreen
//
//  Accent footer that expands typeahead preview into the full interleaved list.
//

import SwiftUI

/// Orange “View all results for …” control at the bottom of the typeahead preview.
struct SearchViewAllRow: View {
    let query: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("View all results for \"\(query)\"")
                .font(DesignTypography.chip.weight(.semibold))
                .foregroundStyle(DesignTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View all results for \(query)")
        .accessibilityHint("Shows a full ranked list with filters")
    }
}
