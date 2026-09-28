//
//  PersonDetailDTO.swift
//  TheSilverScreen
//

import Foundation

struct PersonExternalIDsDTO: Decodable, Sendable {
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
}

struct PersonImagesDTO: Decodable, Sendable {
    let profiles: [MovieImageDTO]?
}

/// One entry from `combined_credits.cast` or `combined_credits.crew`.
struct PersonCombinedCreditDTO: Decodable, Sendable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let genreIDs: [Int]?
    let character: String?
    let job: String?
    /// TMDB crew department, such as "Directing". Nil on cast entries and when the payload omits it.
    let department: String?
    let popularity: Double?
    /// Nil when the combined-credit payload omits `vote_average`.
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case genreIDs = "genre_ids"
        case character
        case job
        case department
        case popularity
        case voteAverage = "vote_average"
    }
}

struct PersonCombinedCreditsDTO: Decodable, Sendable {
    let cast: [PersonCombinedCreditDTO]?
    let crew: [PersonCombinedCreditDTO]?
}

/// TMDB `/person/{id}` payload, including optional `append_to_response` sections.
struct PersonDetailDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double?
    let images: PersonImagesDTO?
    let combinedCredits: PersonCombinedCreditsDTO?
    let externalIds: PersonExternalIDsDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case biography
        case birthday
        case deathday
        case placeOfBirth = "place_of_birth"
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case popularity
        case images
        case combinedCredits = "combined_credits"
        case externalIds = "external_ids"
    }
}
