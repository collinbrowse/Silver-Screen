//
//  TVSeriesDTO.swift
//  TheSilverScreen
//
//  TMDB payloads for series, season, and episode detail. Internal to the data layer.
//

import Foundation

struct TVSeriesSummaryDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let posterPath: String?
    let firstAirDate: String?
    let genreIDs: [Int]?
    let voteAverage: Double?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case genreIDs = "genre_ids"
        case voteAverage = "vote_average"
        case popularity
    }
}

struct TVCreatorDTO: Decodable, Sendable {
    let id: Int
    let name: String?
}

struct TVSeasonSummaryDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let seasonNumber: Int
    let episodeCount: Int?
    let airDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
        case posterPath = "poster_path"
    }
}

struct TVAggregateRoleDTO: Decodable, Sendable {
    let character: String?
    let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case character
        case episodeCount = "episode_count"
    }
}

struct TVAggregateJobDTO: Decodable, Sendable {
    let job: String?
    let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case job
        case episodeCount = "episode_count"
    }
}

struct TVAggregateCastDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let profilePath: String?
    let knownForDepartment: String?
    let totalEpisodeCount: Int?
    let roles: [TVAggregateRoleDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case totalEpisodeCount = "total_episode_count"
        case roles
    }
}

struct TVAggregateCrewDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let profilePath: String?
    let department: String?
    let knownForDepartment: String?
    let totalEpisodeCount: Int?
    let jobs: [TVAggregateJobDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profilePath = "profile_path"
        case department
        case knownForDepartment = "known_for_department"
        case totalEpisodeCount = "total_episode_count"
        case jobs
    }
}

struct TVAggregateCreditsDTO: Decodable, Sendable {
    let cast: [TVAggregateCastDTO]?
    let crew: [TVAggregateCrewDTO]?

    enum CodingKeys: String, CodingKey {
        case cast
        case crew
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cast = try Self.lossy(TVAggregateCastDTO.self, from: container, key: .cast)
        crew = try Self.lossy(TVAggregateCrewDTO.self, from: container, key: .crew)
    }

    /// A bad person is skipped. A value that is not a list still fails this section.
    private static func lossy<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> [T]? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        var unkeyed = try container.nestedUnkeyedContainer(forKey: key)
        var items: [T] = []
        while !unkeyed.isAtEnd {
            let element = try unkeyed.decode(OptionalElement<T>.self)
            if let value = element.value {
                items.append(value)
            }
        }
        return items
    }
}

struct TVSeriesResultsDTO: Decodable, Sendable {
    let results: [TVSeriesSummaryDTO]?

    enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.results), try !container.decodeNil(forKey: .results) else {
            results = nil
            return
        }
        var unkeyed = try container.nestedUnkeyedContainer(forKey: .results)
        var items: [TVSeriesSummaryDTO] = []
        while !unkeyed.isAtEnd {
            let element = try unkeyed.decode(OptionalElement<TVSeriesSummaryDTO>.self)
            if let value = element.value {
                items.append(value)
            }
        }
        results = items
    }
}

/// One array element. A malformed element becomes nil so the rest of the list survives.
private struct OptionalElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

struct TVSeriesDetailDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let genres: [MovieGenreDTO]?
    let createdBy: [TVCreatorDTO]?
    let seasons: [TVSeasonSummaryDTO]?
    let images: MovieImagesDTO?
    let aggregateCredits: TVAggregateCreditsDTO?
    let recommendations: TVSeriesResultsDTO?
    let voteAverage: Double?
    let popularity: Double?
    /// Appended sections that were present but could not be decoded.
    let sectionFailures: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case genres
        case createdBy = "created_by"
        case seasons
        case images
        case aggregateCredits = "aggregate_credits"
        case recommendations
        case voteAverage = "vote_average"
        case popularity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        firstAirDate = try container.decodeIfPresent(String.self, forKey: .firstAirDate)
        lastAirDate = try container.decodeIfPresent(String.self, forKey: .lastAirDate)
        genres = try container.decodeIfPresent([MovieGenreDTO].self, forKey: .genres)
        createdBy = try container.decodeIfPresent([TVCreatorDTO].self, forKey: .createdBy)
        seasons = try container.decodeIfPresent([TVSeasonSummaryDTO].self, forKey: .seasons)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
        var failures: [String] = []
        images = Self.optionalSection(MovieImagesDTO.self, from: container, key: .images, failures: &failures)
        aggregateCredits = Self.optionalSection(TVAggregateCreditsDTO.self, from: container, key: .aggregateCredits, failures: &failures)
        recommendations = Self.optionalSection(TVSeriesResultsDTO.self, from: container, key: .recommendations, failures: &failures)
        sectionFailures = failures
    }

    private static func optionalSection<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        failures: inout [String]
    ) -> T? {
        guard container.contains(key) else { return nil }
        do {
            return try container.decode(T.self, forKey: key)
        } catch {
            failures.append(key.stringValue)
            return nil
        }
    }
}

struct TVEpisodeSummaryDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let overview: String?
    let episodeNumber: Int
    let airDate: String?
    let stillPath: String?
    let crew: [CrewMemberDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case stillPath = "still_path"
        case crew
    }
}

struct TVSeasonDetailDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let overview: String?
    let seasonNumber: Int
    let airDate: String?
    let posterPath: String?
    let episodes: [TVEpisodeSummaryDTO]?
    let images: MovieImagesDTO?
    let aggregateCredits: TVAggregateCreditsDTO?
    let voteAverage: Double?
    let sectionFailures: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case seasonNumber = "season_number"
        case airDate = "air_date"
        case posterPath = "poster_path"
        case episodes
        case images
        case aggregateCredits = "aggregate_credits"
        case voteAverage = "vote_average"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        seasonNumber = try container.decode(Int.self, forKey: .seasonNumber)
        airDate = try container.decodeIfPresent(String.self, forKey: .airDate)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        episodes = try container.decodeIfPresent([TVEpisodeSummaryDTO].self, forKey: .episodes)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        var failures: [String] = []
        images = Self.optionalSection(MovieImagesDTO.self, from: container, key: .images, failures: &failures)
        aggregateCredits = Self.optionalSection(TVAggregateCreditsDTO.self, from: container, key: .aggregateCredits, failures: &failures)
        sectionFailures = failures
    }

    private static func optionalSection<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        failures: inout [String]
    ) -> T? {
        guard container.contains(key) else { return nil }
        do {
            return try container.decode(T.self, forKey: key)
        } catch {
            failures.append(key.stringValue)
            return nil
        }
    }
}

struct TVEpisodeCreditsDTO: Decodable, Sendable {
    let cast: [CastMemberDTO]?
    let crew: [CrewMemberDTO]?
    let guestStars: [CastMemberDTO]?

    enum CodingKeys: String, CodingKey {
        case cast
        case crew
        case guestStars = "guest_stars"
    }
}

struct TVEpisodeDetailDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let overview: String?
    let episodeNumber: Int
    let airDate: String?
    let stillPath: String?
    let crew: [CrewMemberDTO]?
    let guestStars: [CastMemberDTO]?
    let credits: TVEpisodeCreditsDTO?
    let images: MovieImagesDTO?
    let voteAverage: Double?
    let sectionFailures: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case stillPath = "still_path"
        case crew
        case guestStars = "guest_stars"
        case credits
        case images
        case voteAverage = "vote_average"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        episodeNumber = try container.decode(Int.self, forKey: .episodeNumber)
        airDate = try container.decodeIfPresent(String.self, forKey: .airDate)
        stillPath = try container.decodeIfPresent(String.self, forKey: .stillPath)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        crew = try container.decodeIfPresent([CrewMemberDTO].self, forKey: .crew)
        guestStars = try container.decodeIfPresent([CastMemberDTO].self, forKey: .guestStars)
        var failures: [String] = []
        credits = Self.optionalSection(TVEpisodeCreditsDTO.self, from: container, key: .credits, failures: &failures)
        images = Self.optionalSection(MovieImagesDTO.self, from: container, key: .images, failures: &failures)
        sectionFailures = failures
    }

    private static func optionalSection<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        failures: inout [String]
    ) -> T? {
        guard container.contains(key) else { return nil }
        do {
            return try container.decode(T.self, forKey: key)
        } catch {
            failures.append(key.stringValue)
            return nil
        }
    }
}

struct PersonSummaryDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case popularity
    }
}
