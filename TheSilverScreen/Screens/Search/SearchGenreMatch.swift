//
//  SearchGenreMatch.swift
//  TheSilverScreen
//
//  Genre names the query starts, so "hor" finds Horror and "sci" finds Science Fiction.
//

import Foundation

enum SearchGenreMatch {
    static func movieGenreIDs(matching query: String) -> [Int] {
        ids(in: MovieGenreCatalog.namesByID, matching: query)
    }

    static func tvGenreIDs(matching query: String) -> [Int] {
        ids(in: TVGenreCatalog.namesByID, matching: query)
    }

    private static func ids(in namesByID: [Int: String], matching query: String) -> [Int] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3 else { return [] }
        return namesByID.compactMap { id, name in
            name.range(of: needle, options: [.caseInsensitive, .anchored]) != nil ? id : nil
        }.sorted()
    }
}
