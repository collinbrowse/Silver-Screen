//
//  MovieGenreCatalog.swift
//  TheSilverScreen
//

import Foundation

/// Static TMDB movie genre id → name map. IDs are stable; avoids a network round-trip when a list is saved.
enum MovieGenreCatalog {
    static let namesByID: [Int: String] = [
        28: "Action",
        12: "Adventure",
        16: "Animation",
        35: "Comedy",
        80: "Crime",
        99: "Documentary",
        18: "Drama",
        10751: "Family",
        14: "Fantasy",
        36: "History",
        27: "Horror",
        10402: "Music",
        9648: "Mystery",
        10749: "Romance",
        878: "Science Fiction",
        10770: "TV Movie",
        53: "Thriller",
        10752: "War",
        37: "Western",
    ]

    static func names(for ids: [Int]) -> [String] {
        ids.compactMap { namesByID[$0] }
    }

    static func ids(for names: [String]) -> [Int] {
        let idsByName = Dictionary(uniqueKeysWithValues: namesByID.map { ($0.value, $0.key) })
        return names.compactMap { idsByName[$0] }
    }
}
