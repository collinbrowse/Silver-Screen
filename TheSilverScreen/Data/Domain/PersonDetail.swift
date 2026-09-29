//
//  PersonDetail.swift
//  TheSilverScreen
//

import Foundation

/// Which credit list a person-page carousel and its View All screen show.
///
/// `cast` and `crew` stay JSON strings so a navigation path saved by an older build still restores.
enum CreditDepartment: Sendable, Hashable {
    /// Cast credits.
    case cast
    /// Crew jobs that were not already shown in the leading section.
    case crew
    /// Titles where the job is Director.
    case directing
    /// Titles whose job is in the writer set.
    case writing
    /// Crew whose TMDB department matches, such as Production or Camera.
    case named(String)
}

extension CreditDepartment: Codable {
    private enum CodingKeys: String, CodingKey {
        case named
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.named) {
            self = .named(try container.decode(String.self, forKey: .named))
            return
        }
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
            case "cast": self = .cast
            case "crew": self = .crew
            case "directing": self = .directing
            case "writing": self = .writing
            default:
                throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown credit department"
                )
                )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
            case .cast:
                var container = encoder.singleValueContainer()
                try container.encode("cast")
            case .crew:
                var container = encoder.singleValueContainer()
                try container.encode("crew")
            case .directing:
                var container = encoder.singleValueContainer()
                try container.encode("directing")
            case .writing:
                var container = encoder.singleValueContainer()
                try container.encode("writing")
            case .named(let name):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .named)
        }
    }
}

/// Movie or TV credit on a person.
enum CreditMediaType: String, Sendable, Hashable {
    case movie
    case tv
}

/// One crew job on a title. Cast credits leave `jobs` empty and use `roleLabel` for the character.
struct PersonCreditJob: Sendable, Equatable, Hashable {
    /// TMDB department, such as "Directing". Empty when the payload omitted it.
    let department: String
    let job: String
}

/// One cast or crew credit for a person, spanning movies and TV.
struct PersonCredit: Sendable, Identifiable, Equatable, Hashable {
    /// Stable identity across media types so movie 100 and TV 100 never collide.
    var id: String { "\(mediaType.rawValue)-\(mediaID)" }
    let mediaType: CreditMediaType
    let mediaID: Int
    let title: String
    let posterPath: String?
    let releaseDate: Date?
    let genreIDs: [Int]
    /// Character name (cast) or the jobs included in this copy of the credit.
    let roleLabel: String
    /// Crew jobs on this title, in payload order. Empty for cast.
    let jobs: [PersonCreditJob]
    /// TMDB popularity of the title. Breaks ties when two credits are equally recognizable.
    let popularity: Double
    /// TMDB user score copied onto a list entry. Zero when the payload omitted it.
    let voteAverage: Double

    init(
        mediaType: CreditMediaType,
        mediaID: Int,
        title: String,
        posterPath: String?,
        releaseDate: Date?,
        genreIDs: [Int],
        roleLabel: String,
        jobs: [PersonCreditJob] = [],
        popularity: Double,
        voteAverage: Double
    ) {
        self.mediaType = mediaType
        self.mediaID = mediaID
        self.title = title
        self.posterPath = posterPath
        self.releaseDate = releaseDate
        self.genreIDs = genreIDs
        self.roleLabel = roleLabel
        self.jobs = jobs
        self.popularity = popularity
        self.voteAverage = voteAverage
    }

    /// Copy that keeps only `matchingJobs`, with `roleLabel` rebuilt from those jobs.
    func keepingJobs(_ matchingJobs: [PersonCreditJob]) -> PersonCredit {
        PersonCredit(
            mediaType: mediaType,
            mediaID: mediaID,
            title: title,
            posterPath: posterPath,
            releaseDate: releaseDate,
            genreIDs: genreIDs,
            roleLabel: matchingJobs.map(\.job).joined(separator: ", "),
            jobs: matchingJobs,
            popularity: popularity,
            voteAverage: voteAverage
        )
    }
}

/// Person detail returned by TMDB `person/{id}` with appended credits, images, and external ids.
struct PersonDetail: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let biography: String
    let birthday: Date?
    let deathday: Date?
    let placeOfBirth: String?
    let profilePath: String?
    let knownForDepartment: String?
    let imdbID: String?
    let images: [MovieImage]
    /// Cast credits, most recognizable roles first.
    let castCredits: [PersonCredit]
    /// Crew credits, most recognizable titles first. Jobs on the same title are merged.
    let crewCredits: [PersonCredit]
    /// TMDB popularity copied onto a people-list entry. Zero when the payload omitted it.
    let popularity: Double
}
