//
//  ReviewPromptPresenter.swift
//  SilverScreen
//
//  Asks StoreKit for a review when `ReviewPrompter` says so, and shares the
//  prompter with every editor sheet below it.
//

import StoreKit
import SwiftUI

/// Applied once at the root so sheets presented anywhere in the app report rating saves.
struct ReviewPromptPresenter: ViewModifier {
    let prompter: ReviewPrompter
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
            .environment(prompter)
            .task(id: prompter.requestCount) {
                guard prompter.requestCount > 0 else { return }
                // Let the editor sheet finish dismissing so the system prompt is not lost under it.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                requestReview()
            }
    }
}
