//
//  MovieSummaryDTO.swift
//  TheSilverScreen
//

import Foundation

struct MovieListDTO: Decodable, Sendable {
    let page: Int
    let results: [MovieSummaryDTO]
    let totalPages: Int
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case page
        case results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

/// Decodes one TMDB movie result element. Kept internal to the data layer.
struct MovieSummaryDTO: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let releaseDate: String
    let voteAverage: Double
    let genreIDs: [Int]
    let popularity: Double

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
        case popularity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
        voteAverage = try container.decode(Double.self, forKey: .voteAverage)
        genreIDs = try container.decodeIfPresent([Int].self, forKey: .genreIDs) ?? []
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity) ?? 0
    }
}
