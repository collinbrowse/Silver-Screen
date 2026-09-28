//
//  MovieImage.swift
//  TheSilverScreen
//

import Foundation

struct MovieImage: Sendable, Identifiable, Equatable, Hashable {
    /// Stable identity from the file path (TMDB has no numeric id on image objects).
    var id: String { filePath }
    let filePath: String
    let voteAverage: Double
}
