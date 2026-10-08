//
//  TrailerPlayerView.swift
//  TheSilverScreen
//
//  Plays an official trailer on YouTube's watch page.
//

import SwiftUI
import WebKit

/// Sheet that plays one trailer. The video stays in YouTube's player.
struct TrailerPlayerView: View {
    let trailer: MediaTrailer

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubeEmbedView(url: trailer.watchURL)
                .ignoresSafeArea(edges: .bottom)
                .background(Color(.systemBackground))
                .accessibilityLabel(trailer.title)
                .navigationTitle(trailer.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Presents the YouTube player for the trailer the user chose.
    /// Dismissing the sheet clears `loadingID` so the pill's spinner returns to a play icon.
    func trailerPlayer(_ selection: Binding<MediaTrailer?>, loadingID: Binding<String?>) -> some View {
        sheet(item: selection, onDismiss: {
            loadingID.wrappedValue = nil
            }) { trailer in
            TrailerPlayerView(trailer: trailer)
        }
    }
}

/// Shows a spinner on the tapped pill first, then presents the player so the web view loads after that icon change.
@MainActor
func presentTrailer(
    _ trailer: MediaTrailer,
    loadingID: Binding<String?>,
    selection: Binding<MediaTrailer?>
) {
    guard loadingID.wrappedValue == nil else { return }
    loadingID.wrappedValue = trailer.id
    Task { @MainActor in
        // Let the pill redraw as a spinner before the sheet creates the web view.
        try? await Task.sleep(for: .milliseconds(100))
        guard loadingID.wrappedValue == trailer.id else { return }
        selection.wrappedValue = trailer
    }
}
