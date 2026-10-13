//
//  TMDBRequestBuilder.swift
//  SilverScreen
//
//  Builds authenticated TMDB v3 requests. The read-access token goes in the
//  Authorization header, never the query string — see .cursor/rules/secrets.mdc.
//

import Foundation

struct TMDBRequestBuilder: Sendable {
    private let baseURL: URL
    private let accessToken: String

    init(
        accessToken: String,
        baseURL: URL = URL(string: "https://api.themoviedb.org/3")!
    ) {
        self.accessToken = accessToken
        self.baseURL = baseURL
    }

    func get(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: baseURL.appendingPathComponent(trimmed),
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
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
