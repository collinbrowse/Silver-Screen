//
//  WatchDateRow.swift
//  SilverScreen
//
//  The day row of the Log and season rewatch sheets. A grey x beside the date picker
//  makes the watch undated; tapping the "Unknown watch date" row that replaces it
//  brings the picker back with the date it last held.
//

import SwiftUI

struct WatchDateRow: View {
    @Binding var watchedOn: Date
    /// False for an undated watch, which has no day.
    @Binding var isDateKnown: Bool

    var body: some View {
        if isDateKnown {
            HStack(spacing: DesignSpacing.sm) {
                DatePicker(
                    "Watched on",
                    selection: $watchedOn,
                    in: ...Date(),
                    displayedComponents: .date
                )
                Button {
                    isDateKnown = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        // An explicit grey: `.secondary` inside a button takes the tint.
                        .foregroundStyle(DesignTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                // Borderless, so a Form row does not turn the whole row into this button.
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear watch date")
                .accessibilityHint("Saves the watch with an unknown date")
            }
        } else {
            Button {
                isDateKnown = true
            } label: {
                Text("Unknown watch date")
                    .foregroundStyle(DesignTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Shows the date picker")
        }
    }
}
