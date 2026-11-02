//
//  WatchDateRow.swift
//  SilverScreen
//
//  The day row of the Log and season rewatch sheets. A grey x beside the date picker
//  makes the watch undated; the "Unknown watch date" row that replaces it has a grey
//  plus that brings the picker back with the date it last held.
//

import SwiftUI

struct WatchDateRow: View {
    @Binding var watchedOn: Date
    /// False for an undated watch, which has no day.
    @Binding var isDateKnown: Bool

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            if isDateKnown {
                DatePicker(
                    "Watched on",
                    selection: $watchedOn,
                    in: ...Date(),
                    displayedComponents: .date
                )
                iconButton("xmark.circle.fill", label: "Clear watch date") {
                    isDateKnown = false
                }
                .accessibilityHint("Saves the watch with an unknown date")
            } else {
                Text("Unknown watch date")
                    .frame(maxWidth: .infinity, alignment: .leading)
                iconButton("plus.circle.fill", label: "Add watch date") {
                    isDateKnown = true
                }
            }
        }
    }

    /// The grey circle button at the end of the row. Same size in both states, so the
    /// row keeps its height when the date is cleared or added back.
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                // An explicit grey: `.secondary` inside a button takes the tint.
                .foregroundStyle(DesignTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Borderless, so a Form row does not turn the whole row into this button.
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}
