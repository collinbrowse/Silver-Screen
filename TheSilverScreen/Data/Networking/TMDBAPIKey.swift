//
//  TMDBAPIKey.swift
//  TheSilverScreen
//
//  Reads the TMDB API key from Info.plist for the data layer.
//

import Foundation

enum TMDBAPIKey {
    static func fromBundle(_ bundle: Bundle = .main) throws -> String {
        guard let key = bundle.object(forInfoDictionaryKey: "TMDBAPIKey") as? String else {
            throw AppError.missingAPIKey
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            throw AppError.missingAPIKey
        }
        return trimmed
    }
}
