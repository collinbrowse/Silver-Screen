//
//  EmptyStateView.swift
//  TheSilverScreen
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    init(
        title: String = "Nothing Here",
        message: String,
        systemImage: String = "tray"
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
