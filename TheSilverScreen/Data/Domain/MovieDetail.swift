//
//  MovieDetail.swift
//  TheSilverScreen
//

import Foundation

struct MovieGenre: Sendable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct MovieDetail: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: Date?
    let voteAverage: Double
    /// TMDB popularity copied onto a list entry. Zero when the payload omitted it.
    let popularity: Double
    /// Runtime in minutes. `nil` when TMDB omitted it or reported zero.
    let runtimeMinutes: Int?
    let genres: [MovieGenre]
    /// Official YouTube trailers, in TMDB order.
    let trailers: [MediaTrailer]
    /// Subscription streaming services for the user's region, when TMDB lists them.
    let streamingProviders: [StreamingProvider]
    let budget: Int
    let revenue: Int
    let images: [MovieImage]
    let cast: [CastMember]
    let crew: [CrewMember]
    let similar: [Movie]
    let collection: MovieCollectionRef?

    /// Domain movie for this detail, including popularity saved on a list.
    func asMovie() -> Movie {
        Movie(
            id: id,
            title: title,
            posterPath: posterPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genreIDs: genres.map(\.id),
            popularity: popularity
        )
    }
}
