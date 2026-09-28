//
//  CatalogMedia.swift
//  TheSilverScreen
//
//  Display rows for browsable movie, TV, and people lists. Genre names and
//  dates are resolved here so list views only render strings.
//

import Foundation

struct CatalogMovieRow: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let posterPath: String?
    let genreNames: [String]
    let formattedReleaseDate: String
    let genreIDs: [Int]
    let releaseDate: Date?
    let voteAverage: Double
    /// Keeps a name search in popularity order after later pages arrive.
    let popularity: Double
    /// Personal score, when this movie has one.
    var formattedUserScore: String?
    /// Day that score was chosen.
    var formattedRatedOn: String?

    init(movie: Movie) {
        id = movie.id
        title = movie.title
        posterPath = movie.posterPath
        genreIDs = movie.genreIDs
        genreNames = MovieGenreCatalog.names(for: movie.genreIDs)
        releaseDate = movie.releaseDate
        voteAverage = movie.voteAverage
        popularity = movie.popularity
        formattedReleaseDate = DisplayDate.day(movie.releaseDate)
        formattedUserScore = nil
        formattedRatedOn = nil
    }

    func withUserScore(_ saved: SavedUserScore?) -> CatalogMovieRow {
        var copy = self
        copy.formattedUserScore = saved?.formatted
        copy.formattedRatedOn = saved?.ratedOn
        return copy
    }

    func asMovie() -> Movie {
        Movie(
            id: id,
            title: title,
            posterPath: posterPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genreIDs: genreIDs,
            popularity: popularity
        )
    }
}

struct CatalogTVRow: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let posterPath: String?
    let genreNames: [String]
    let formattedFirstAirDate: String
    let genreIDs: [Int]
    let firstAirDate: Date?
    /// TMDB user score copied onto a list entry. Zero when the payload omitted it.
    let voteAverage: Double
    /// Keeps a name search in popularity order after later pages arrive.
    let popularity: Double
    /// Personal score, when this series has one.
    var formattedUserScore: String?
    /// Day that score was chosen.
    var formattedRatedOn: String?

    init(series: TVSeriesSummary) {
        id = series.id
        name = series.name
        posterPath = series.posterPath
        genreIDs = series.genreIDs
        genreNames = TVGenreCatalog.names(for: series.genreIDs)
        firstAirDate = series.firstAirDate
        voteAverage = series.voteAverage
        popularity = series.popularity
        formattedFirstAirDate = DisplayDate.day(series.firstAirDate)
        formattedUserScore = nil
        formattedRatedOn = nil
    }

    func withUserScore(_ saved: SavedUserScore?) -> CatalogTVRow {
        var copy = self
        copy.formattedUserScore = saved?.formatted
        copy.formattedRatedOn = saved?.ratedOn
        return copy
    }
}

/// A person as they appear in popular and search lists — not a full biography.
struct PersonSummary: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    /// TMDB popularity. Zero when the payload omitted it.
    var popularity: Double = 0
}

struct PersonPage: Sendable, Equatable {
    let people: [PersonSummary]
    let page: Int
    let hasMore: Bool
}

struct CatalogPersonRow: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double

    init(person: PersonSummary) {
        id = person.id
        name = person.name
        profilePath = person.profilePath
        let department = person.knownForDepartment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        knownForDepartment = (department?.isEmpty == false) ? department : nil
        popularity = person.popularity
    }
}
