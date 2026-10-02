//
//  TVSeries.swift
//  TheSilverScreen
//
//  Domain models for a TV series, one season, and one episode.
//

import Foundation

/// Lightweight series used by recommendations and popular / search lists.
struct TVSeriesSummary: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let posterPath: String?
    let firstAirDate: Date?
    let genreIDs: [Int]
    /// Used when Browse merges a TV page with a movie page. Popular lists may omit it.
    var voteAverage: Double = 0
    /// Used when Browse merges a Popular page. Zero when the payload omitted it.
    var popularity: Double = 0
}

struct TVSeriesPage: Sendable, Equatable {
    let series: [TVSeriesSummary]
    let page: Int
    let hasMore: Bool
}

/// A person on a cast, guest-star, or director/writer carousel.
struct TVCredit: Sendable, Identifiable, Equatable, Hashable {
    /// Person id. Each carousel shows a person at most once.
    let id: Int
    let name: String
    /// Character name for cast and guests; job titles for directors and writers.
    let role: String
    let profilePath: String?
    /// Aggregate episode count. Zero for a single episode's credits.
    let episodeCount: Int
    let knownForDepartment: String?
}

struct TVSeasonSummary: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int
    let airDate: Date?
    let posterPath: String?
}

struct TVEpisodeSummary: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let episodeNumber: Int
    let overview: String
    let airDate: Date?
    let stillPath: String?
    /// Every credited director, joined. Nil when the episode lists none.
    let directorName: String?

    /// `Director: …` or `Director: unknown` when the season payload has no director.
    var directorLine: String {
        guard let directorName, !directorName.isEmpty else { return "Director: unknown" }
        return "Director: \(directorName)"
    }
}

struct TVSeriesDetail: Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let firstAirDate: Date?
    let lastAirDate: Date?
    let genres: [MovieGenre]
    /// Official YouTube trailers, in TMDB order.
    let trailers: [MediaTrailer]
    /// Subscription streaming services for the user's region, when TMDB lists them.
    let streamingProviders: [StreamingProvider]
    /// TMDB user score, 0–10. Zero when the payload omitted it.
    let voteAverage: Double
    /// TMDB popularity copied onto a list entry. Zero when the payload omitted it.
    let popularity: Double
    let creators: [String]
    let images: [MovieImage]
    /// Seasons sorted by season number, earliest first.
    let seasons: [TVSeasonSummary]
    let recommendations: [TVSeriesSummary]
    /// Cast sorted by episode count, highest first, capped at 30.
    let cast: [TVCredit]
    /// Directors and writers, same sort and cap as cast.
    let directorsAndWriters: [TVCredit]
}

struct TVSeasonDetail: Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let overview: String
    let airDate: Date?
    let posterPath: String?
    /// TMDB user score, 0–10. Zero when the payload omitted it.
    let voteAverage: Double
    let images: [MovieImage]
    let cast: [TVCredit]
    let directorsAndWriters: [TVCredit]
    let episodes: [TVEpisodeSummary]
    /// Official YouTube trailers, in TMDB order.
    let trailers: [MediaTrailer]
}

struct TVEpisodeDetail: Sendable, Equatable, Identifiable {
    let id: Int
    let title: String
    let episodeNumber: Int
    let overview: String
    let airDate: Date?
    let stillPath: String?
    /// TMDB user score, 0–10. Zero when the payload omitted it.
    let voteAverage: Double
    let images: [MovieImage]
    let cast: [TVCredit]
    let guestStars: [TVCredit]
    let directorsAndWriters: [TVCredit]
    /// Official YouTube trailers, in TMDB order.
    let trailers: [MediaTrailer]
}

/// Season title from TMDB's name. The name already includes the number (`Season 1`).
enum SeasonTitle {
    static func display(name: String, number: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if number == 0 {
            return "Specials"
        }
        return "Season \(number)"
    }
}
