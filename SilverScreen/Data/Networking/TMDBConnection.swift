//
//  TMDBConnection.swift
//  SilverScreen
//
//  Where TMDB requests go. The default is TMDB itself, signed with the bundled
//  token. When TMDB_BASE_URL points anywhere else, it is the Silver Screen proxy
//  (worker/), which adds the token server-side, so the app sends none.
//

import Foundation

/// TMDB base URL plus the bearer token the app signs with, if any.
struct TMDBConnection: Sendable, Equatable {
    static let directBaseURL = URL(string: "https://api.themoviedb.org/3")!
    static let directHost = "api.themoviedb.org"

    let baseURL: URL
    /// Bearer token for direct calls. Nil for the proxy, which adds its own.
    let accessToken: String?

    /// Calls TMDB directly and signs each request with `accessToken`.
    static func direct(accessToken: String, baseURL: URL = directBaseURL) -> TMDBConnection {
        TMDBConnection(baseURL: baseURL, accessToken: accessToken)
    }

    /// Calls the proxy at `baseURL` (including `/3`) and sends no token.
    static func proxy(baseURL: URL) -> TMDBConnection {
        TMDBConnection(baseURL: baseURL, accessToken: nil)
    }

    static func fromBundle(_ bundle: Bundle = .main) throws -> TMDBConnection {
        try resolve(
            baseURL: bundle.object(forInfoDictionaryKey: "TMDBBaseURL") as? String,
            accessToken: bundle.object(forInfoDictionaryKey: "TMDBAccessToken") as? String
        )
    }

    /// Picks direct or proxy from the Info.plist values. An empty or unsubstituted base URL
    /// means direct TMDB. Direct needs a valid token; the proxy ignores any token it is given.
    /// A base URL that is not https with a host fails at launch rather than on the first request.
    static func resolve(baseURL rawBaseURL: String?, accessToken: String?) throws -> TMDBConnection {
        // xcconfig treats `//` as a comment, so the URL is written `https:/$()/…`.
        let trimmed = (rawBaseURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$()", with: "")
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return .direct(accessToken: try TMDBAccessToken.validated(accessToken))
        }
        guard let url = URL(string: trimmed), url.scheme == "https", let host = url.host(), !host.isEmpty else {
            throw AppError.invalidBaseURL
        }
        if host == directHost {
            return .direct(accessToken: try TMDBAccessToken.validated(accessToken), baseURL: url)
        }
        return .proxy(baseURL: url)
    }
}
