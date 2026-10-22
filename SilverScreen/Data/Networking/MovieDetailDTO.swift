//
//  MovieDetailDTO.swift
//  SilverScreen
//

import Foundation

struct MovieGenreDTO: Decodable, Sendable {
    let id: Int
    let name: String
}

struct MovieImageDTO: Decodable, Sendable {
    let filePath: String
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case voteAverage = "vote_average"
    }
}

struct MovieImagesDTO: Decodable, Sendable {
    let backdrops: [MovieImageDTO]?
    let posters: [MovieImageDTO]?
    /// Episode and season stills. Absent on movie payloads.
    let stills: [MovieImageDTO]?

    enum CodingKeys: String, CodingKey {
        case backdrops, posters, stills
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backdrops = try container.decodeLossyArrayIfPresent(MovieImageDTO.self, forKey: .backdrops)
        posters = try container.decodeLossyArrayIfPresent(MovieImageDTO.self, forKey: .posters)
        stills = try container.decodeLossyArrayIfPresent(MovieImageDTO.self, forKey: .stills)
    }
}

struct CastMemberDTO: Decodable, Sendable {
    let id: Int
    let creditID: String?
    let name: String?
    let character: String?
    let profilePath: String?
    let order: Int?
    let knownForDepartment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case creditID = "credit_id"
        case name
        case character
        case profilePath = "profile_path"
        case order
        case knownForDepartment = "known_for_department"
    }
}

struct CrewMemberDTO: Decodable, Sendable {
    let id: Int
    let creditID: String?
    let name: String?
    let job: String?
    let department: String?
    let profilePath: String?
    let knownForDepartment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case creditID = "credit_id"
        case name
        case job
        case department
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
    }
}

struct MovieCreditsDTO: Decodable, Sendable {
    let cast: [CastMemberDTO]?
    let crew: [CrewMemberDTO]?

    enum CodingKeys: String, CodingKey {
        case cast, crew
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cast = try container.decodeLossyArrayIfPresent(CastMemberDTO.self, forKey: .cast)
        crew = try container.decodeLossyArrayIfPresent(CrewMemberDTO.self, forKey: .crew)
    }
}

struct MovieCollectionRefDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case posterPath = "poster_path"
    }
}

struct MovieCollectionDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let parts: [MovieSummaryDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case posterPath = "poster_path"
        case parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        parts = try container.decodeLossyArrayIfPresent(MovieSummaryDTO.self, forKey: .parts)
    }
}

struct ReviewAuthorDTO: Decodable, Sendable {
    let username: String?
}

/// TMDB review object. Movie and TV review payloads share this shape.
struct ReviewDTO: Decodable, Sendable {
    let id: String
    let author: String?
    let content: String?
    let updatedAt: String?
    let authorDetails: ReviewAuthorDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case content
        case updatedAt = "updated_at"
        case authorDetails = "author_details"
    }
}

struct ReviewPageMetaDTO: Decodable, Sendable {
    let totalResults: Int?

    enum CodingKeys: String, CodingKey {
        case totalResults = "total_results"
    }
}

/// TMDB `/movie/{id}` payload, including optional `append_to_response` sections.
struct MovieDetailDTO: Decodable, Sendable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let voteAverage: Double
    let popularity: Double?
    /// Runtime in minutes. Absent or zero when TMDB does not know it.
    let runtime: Int?
    let genres: [MovieGenreDTO]?
    let budget: Int?
    let revenue: Int?
    let images: MovieImagesDTO?
    let credits: MovieCreditsDTO?
    let similar: MovieListResultsDTO?
    let belongsToCollection: MovieCollectionRefDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case popularity
        case runtime
        case genres
        case budget
        case revenue
        case images
        case credits
        case similar
        case belongsToCollection = "belongs_to_collection"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        voteAverage = try container.decode(Double.self, forKey: .voteAverage)
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
        runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
        genres = try container.decodeLossyArrayIfPresent(MovieGenreDTO.self, forKey: .genres)
        budget = try container.decodeIfPresent(Int.self, forKey: .budget)
        revenue = try container.decodeIfPresent(Int.self, forKey: .revenue)
        images = try container.decodeIfPresent(MovieImagesDTO.self, forKey: .images)
        credits = try container.decodeIfPresent(MovieCreditsDTO.self, forKey: .credits)
        similar = try container.decodeIfPresent(MovieListResultsDTO.self, forKey: .similar)
        belongsToCollection = try container.decodeIfPresent(
            MovieCollectionRefDTO.self,
            forKey: .belongsToCollection
        )
    }
}

struct MovieListResultsDTO: Decodable, Sendable {
    let results: [MovieSummaryDTO]?

    enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeLossyArrayIfPresent(MovieSummaryDTO.self, forKey: .results)
    }
}
