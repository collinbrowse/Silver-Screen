//
//  MovieCollection.swift
//  TheSilverScreen
//

import Foundation

struct MovieCollectionRef: Sendable, Equatable, Hashable {
    let id: Int
    let name: String
    let posterPath: String?
}

/// A TMDB collection: header metadata plus the movies (parts) that belong to it.
struct MovieCollection: Sendable, Equatable, Hashable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let parts: [Movie]
}
