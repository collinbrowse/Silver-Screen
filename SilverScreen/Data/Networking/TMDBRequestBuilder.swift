//
//  TMDBRequestBuilder.swift
//  SilverScreen
//
//  Builds TMDB v3 requests against the configured base URL. Direct calls carry the
//  read-access token in the Authorization header, never the query string — see
//  .cursor/rules/secrets.mdc. Proxy calls carry no token; the proxy adds it.
//

import Foundation

struct TMDBRequestBuilder: Sendable {
    private let connection: TMDBConnection

    init(connection: TMDBConnection) {
        self.connection = connection
    }

    func get(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: connection.baseURL.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw AppError.unknown
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken = connection.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
