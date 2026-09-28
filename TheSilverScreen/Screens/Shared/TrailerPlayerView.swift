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
                .background(Color.black)
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
        .preferredColorScheme(.dark)
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

/// Loads YouTube's watch page. The embed endpoint answers in-app web views with error 152-4.
private struct YouTubeEmbedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.safariUserAgent
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.accessibilityLabel = "Trailer video"
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(Self.request(for: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Mobile Safari. YouTube treats the stock web-view agent as an unidentified embedder.
    private static let safariUserAgent = """
    Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1
    """

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("\(MediaTrailer.embedOrigin.absoluteString)/", forHTTPHeaderField: "Referer")
        return request
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
