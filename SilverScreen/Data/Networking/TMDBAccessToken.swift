//
//  TMDBAccessToken.swift
//  SilverScreen
//
//  Validates the TMDB API Read Access Token from Info.plist for direct calls.
//  Requests send it as a bearer header. A v3 API key is rejected here so it never
//  reaches a URL. Proxy builds ship no token; see TMDBConnection.
//

import Foundation

/// Bundled TMDB read-access token. Missing, unsubstituted, and v3-key values fail at launch.
enum TMDBAccessToken {
    /// Accepts a read-access token. A missing value, an unsubstituted `$(TMDB_ACCESS_TOKEN)`,
    /// and a 32-character v3 API key all fail the same way.
    static func validated(_ raw: String?) throws -> String {
        guard let raw else {
            throw AppError.missingAccessToken
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), !isV3APIKey(trimmed) else {
            throw AppError.missingAccessToken
        }
        return trimmed
    }

    private static let hexDigits = Set("0123456789abcdefABCDEF")

    /// A v3 API key is 32 hex characters and only works as an `api_key` query item.
    private static func isV3APIKey(_ value: String) -> Bool {
        value.count == 32 && value.allSatisfy { hexDigits.contains($0) }
    }
}
