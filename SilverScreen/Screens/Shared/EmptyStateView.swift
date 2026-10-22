//
//  EmptyStateView.swift
//  SilverScreen
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    /// Optional button under the message, such as Get started.
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String = "Nothing Here",
        message: String,
        systemImage: String = "tray",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTheme.accent)
                    .foregroundStyle(DesignTheme.accentOnFill)
            }
        }
    }
}
