//
//  EpisodeWatchButton.swift
//  SilverScreen
//
//  Marks one episode completed or not. Separate from list membership (+).
//

import SwiftUI

struct EpisodeWatchButton: View {
    let isCompleted: Bool
    let accessibilityTitle: String
    /// Eye color while not watched. Rows keep it muted beside the episode text; a
    /// toolbar passes `textPrimary` so the eye does not read as an empty button.
    var idleColor: Color = DesignTheme.textMuted
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isCompleted ? "eye.fill" : "eye")
                .font(.title3)
                .foregroundStyle(isCompleted ? DesignTheme.accent : idleColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // No button style here: `.borderless` pulls a toolbar button out of the
        // vertical bar on iPhone Duo. Row call sites set their own.
        .accessibilityLabel(isCompleted ? "Mark \(accessibilityTitle) not watched" : "Mark \(accessibilityTitle) watched")
        .accessibilityValue(isCompleted ? "Watched" : "Not watched")
    }
}
