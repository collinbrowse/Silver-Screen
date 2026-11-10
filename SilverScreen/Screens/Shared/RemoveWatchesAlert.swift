//
//  RemoveWatchesAlert.swift
//  SilverScreen
//
//  The confirmation before the eye removes more than one watch of a movie or episode.
//  One watch goes straight away, because the toast's Undo covers it.
//

import SwiftUI

/// A pending removal: what to name in the alert, and the work to run on confirm.
struct WatchRemovalRequest {
    let title: String
    let watchCount: Int
    let remove: @MainActor () async -> Void

    /// "Remove all 3 watches of Hope?"
    var alertTitle: String {
        String(localized: "Remove all \(watchCount) watches of \(title)?")
    }

    static let message = String(localized: "Their ratings and reviews go too.")
}

extension View {
    /// Shows `request` when set. `presenting` hands the request to the button, so
    /// dismissing the alert cannot clear it before the confirm runs.
    func removeWatchesAlert(_ request: Binding<WatchRemovalRequest?>) -> some View {
        alert(
            request.wrappedValue?.alertTitle ?? "",
            isPresented: Binding(
                get: { request.wrappedValue != nil },
                set: { if !$0 { request.wrappedValue = nil } }
            ),
            presenting: request.wrappedValue
        ) { pending in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await pending.remove() }
            }
        } message: { _ in
            Text(WatchRemovalRequest.message)
        }
    }
}
