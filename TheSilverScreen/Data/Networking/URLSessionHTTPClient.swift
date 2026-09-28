//
//  URLSessionHTTPClient.swift
//  TheSilverScreen
//

import Foundation

struct URLSessionHTTPClient: HTTPClient, Sendable {
    private let session: URLSession

    init(session: URLSession = URLSessionHTTPClient.makeSession()) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private static func makeSession() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }

    /// A client whose session has a dedicated on-disk cache sized for image bytes. Used by the
    /// image pipeline so decoded-image eviction from `NSCache` falls back to disk instead of the
    /// network, and so posters don't compete with JSON responses in the shared default cache.
    static func images() -> URLSessionHTTPClient {
        URLSessionHTTPClient(session: URLSession(configuration: makeImageConfiguration()))
    }

    static func makeImageConfiguration() -> URLSessionConfiguration {
        let configuration = makeConfiguration()
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: imageCacheDirectory()
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return configuration
    }

    private static func imageCacheDirectory() -> URL? {
        let base = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base?.appendingPathComponent("TheSilverScreenImageCache", isDirectory: true)
    }

    /// Shared transport configuration. We deliberately **fail fast** rather than wait for
    /// connectivity. With `waitsForConnectivity = true`, a cold load in airplane mode does not
    /// return `.notConnectedToInternet`; it parks until `timeoutIntervalForResource` and then fails
    /// as a *timeout* — so the user watches a spinner for the whole interval and then sees the wrong
    /// message ("Request Timed Out") instead of "You're Offline". Turning it off makes the request
    /// fail immediately with `.notConnectedToInternet`, which the transport maps to
    /// `AppError.offline`. Re-introducing dead-zone waiting should ride on an `NWPathMonitor` that
    /// can still fail fast when the device is genuinely offline (the reachability follow-up).
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        return configuration
    }
}
