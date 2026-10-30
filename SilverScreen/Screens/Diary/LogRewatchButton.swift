//
//  LogRewatchButton.swift
//  SilverScreen
//
//  The one way to log a watch of something already watched: under the rating card on
//  movie and episode pages, and at the top of Watch History.
//

import SwiftUI

struct LogRewatchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Log a Rewatch", systemImage: "arrow.counterclockwise")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.accentOnFill)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTheme.accent)
        .controlSize(.large)
        .accessibilityHint("Adds a new watch to your diary, dated today")
    }
}
