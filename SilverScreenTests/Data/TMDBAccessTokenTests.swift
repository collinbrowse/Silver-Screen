//
//  TMDBAccessTokenTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class TMDBAccessTokenTests: XCTestCase {
    func test_validated_rejectsMissingUnsubstitutedAndV3Key() {
        XCTAssertThrowsError(try TMDBAccessToken.validated(nil)) { error in
            XCTAssertEqual(error as? AppError, .missingAccessToken)
        }
        XCTAssertThrowsError(try TMDBAccessToken.validated("   ")) { error in
            XCTAssertEqual(error as? AppError, .missingAccessToken)
        }
        XCTAssertThrowsError(try TMDBAccessToken.validated("$(TMDB_ACCESS_TOKEN)")) { error in
            XCTAssertEqual(error as? AppError, .missingAccessToken)
        }
        // Built, not a literal, so the source scanner does not see a committed v3 key.
        let v3Key = String(repeating: "ab", count: 16)
        XCTAssertThrowsError(try TMDBAccessToken.validated(v3Key)) { error in
            XCTAssertEqual(error as? AppError, .missingAccessToken)
        }
        XCTAssertThrowsError(try TMDBAccessToken.validated(v3Key.uppercased())) { error in
            XCTAssertEqual(error as? AppError, .missingAccessToken)
        }
    }

    func test_validated_acceptsReadAccessToken() throws {
        let token = "read-access-token"
        XCTAssertEqual(try TMDBAccessToken.validated("  \(token)  "), token)
        XCTAssertEqual(try TMDBAccessToken.validated(String(repeating: "z", count: 32)), String(repeating: "z", count: 32))
    }

    func test_missingAccessToken_namesTheReadAccessToken() {
        XCTAssertEqual(
            AppError.missingAccessToken.message,
            "Copy Secrets.example.xcconfig to Secrets.xcconfig and set TMDB_ACCESS_TOKEN to the API Read Access Token on the TMDB API settings page. A v3 API key will not work."
        )
        XCTAssertFalse(AppError.missingAccessToken.isRetryable)
    }
}
