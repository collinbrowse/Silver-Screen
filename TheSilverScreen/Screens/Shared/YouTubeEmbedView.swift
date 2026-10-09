//
//  YouTubeEmbedView.swift
//  TheSilverScreen
//
//  Loads YouTube's watch page. The embed endpoint answers in-app web views with error 152-4.
//

import SwiftUI
import WebKit

struct YouTubeEmbedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.safariUserAgent
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
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
