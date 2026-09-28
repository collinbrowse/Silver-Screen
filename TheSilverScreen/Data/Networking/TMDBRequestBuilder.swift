//
//  TMDBRequestBuilder.swift
//  TheSilverScreen
//
//  Builds authenticated TMDB v3 requests. Appends api_key as a query item.
//  Callers must not log the full URL — see .cursor/rules/secrets.mdc.
//

import Foundation

struct TMDBRequestBuilder: Sendable {
    private let baseURL: URL
    private let apiKey: String

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.themoviedb.org/3")!
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func get(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: baseURL.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items

        guard let url = components.url else {
            throw AppError.unknown
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
