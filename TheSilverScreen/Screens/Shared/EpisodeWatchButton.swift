//
//  EpisodeWatchButton.swift
//  TheSilverScreen
//
//  Marks one episode completed or not. Separate from list membership (+).
//

import SwiftUI

struct EpisodeWatchButton: View {
    let isCompleted: Bool
    let accessibilityTitle: String
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isCompleted ? "eye.fill" : "eye")
                .font(.title3)
                .foregroundStyle(isCompleted ? DesignTheme.accent : DesignTheme.textMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isCompleted ? "Mark \(accessibilityTitle) not watched" : "Mark \(accessibilityTitle) watched")
        .accessibilityValue(isCompleted ? "Watched" : "Not watched")
    }
}
