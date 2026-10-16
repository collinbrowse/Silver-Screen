//
//  TMDBRequestBuilderTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class TMDBRequestBuilderTests: XCTestCase {
    private let token = "eyJhbGciOiJIUzI1NiJ9.test.signature"
    private let proxyURL = URL(string: "https://silverscreen-tmdb.example.workers.dev/3")!

    func test_get_proxy_sendsNoAuthorizationHeader() throws {
        let builder = TMDBRequestBuilder(connection: .proxy(baseURL: proxyURL))

        let request = try builder.get(
            path: "/movie/278",
            queryItems: [URLQueryItem(name: "language", value: "en-US")]
        )

        XCTAssertEqual(request.url?.absoluteString, "https://silverscreen-tmdb.example.workers.dev/3/movie/278?language=en-US")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func test_get_direct_sendsBearerHeaderAndNoTokenInURL() throws {
        let builder = TMDBRequestBuilder(connection: .direct(accessToken: token))

        let request = try builder.get(path: "discover/movie", queryItems: [URLQueryItem(name: "page", value: "2")])

        XCTAssertEqual(request.url?.absoluteString, "https://api.themoviedb.org/3/discover/movie?page=2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertFalse(request.url?.absoluteString.contains(token) ?? true)
    }

    func test_resolve_emptyOrUnsubstitutedBaseURL_isDirectTMDB() throws {
        for raw in [nil, "", "  ", "$(TMDB_BASE_URL)"] {
            let connection = try TMDBConnection.resolve(baseURL: raw, accessToken: token)
            XCTAssertEqual(connection, .direct(accessToken: token), "base URL \(String(describing: raw))")
        }
    }

    func test_resolve_tmdbBaseURL_isDirectAndNeedsAToken() throws {
        let connection = try TMDBConnection.resolve(baseURL: "https:/$()/api.themoviedb.org/3", accessToken: token)
        XCTAssertEqual(connection, .direct(accessToken: token))

        XCTAssertThrowsError(try TMDBConnection.resolve(baseURL: "https://api.themoviedb.org/3", accessToken: "")) { error in
            XCTAssertEqual(error as? AppError, .missingAccessToken)
        }
    }

    func test_resolve_proxyBaseURL_dropsAnyTokenAndNeedsNone() throws {
        let withoutToken = try TMDBConnection.resolve(baseURL: "https:/$()/silverscreen-tmdb.example.workers.dev/3", accessToken: nil)
        let withToken = try TMDBConnection.resolve(baseURL: proxyURL.absoluteString, accessToken: token)

        XCTAssertEqual(withoutToken, .proxy(baseURL: proxyURL))
        XCTAssertEqual(withToken, .proxy(baseURL: proxyURL))
        XCTAssertNil(withToken.accessToken)
    }

    func test_resolve_rejectsNonHTTPSOrHostlessBaseURL() {
        for raw in ["http://silverscreen-tmdb.example.workers.dev/3", "https:", "not a url"] {
            XCTAssertThrowsError(try TMDBConnection.resolve(baseURL: raw, accessToken: token), raw) { error in
                XCTAssertEqual(error as? AppError, .invalidBaseURL)
            }
        }
        XCTAssertFalse(AppError.invalidBaseURL.isRetryable)
        XCTAssertFalse(HTTPTransport.shouldAutomaticallyRetry(.invalidBaseURL))
    }
}
