//
//  BrowseCatalog.swift
//  TheSilverScreen
//
//  Browse selection, Discover query items, and the mixed-list merge.
//  Pages arrive already sorted; the merge only decides which stream's next
//  row is appended, so rows the user has already seen stay put.
//

import Foundation


enum BrowseWindow: String, CaseIterable, Sendable, Equatable {
    case all
    case nowPlaying
    case upcoming

    var title: String {
        switch self {
            case .all: "All"
            case .nowPlaying: "Now Playing"
            case .upcoming: "Upcoming"
        }
    }

    var symbol: String {
        switch self {
            case .all: "square.grid.2x2"
            case .nowPlaying: "ticket"
            case .upcoming: "calendar"
        }
    }
}

enum BrowseSort: String, CaseIterable, Sendable, Equatable {
    case popular
    case topRated
    case alphabetical
    case newest
    case oldest

    var title: String {
        switch self {
            case .popular: "Popular"
            case .topRated: "Top Rated"
            case .alphabetical: "Alphabetical"
            case .newest: "Newest"
            case .oldest: "Oldest"
        }
    }

    var symbol: String {
        switch self {
            case .popular: "flame"
            case .topRated: "star"
            case .alphabetical: "textformat.abc"
            case .newest: "arrow.down"
            case .oldest: "arrow.up"
        }
    }
}

/// One Discover list: movies or TV, already constrained to a window and sort.
enum DiscoverKind: Sendable, Equatable {
    case movie
    case tv

    var path: String {
        switch self {
            case .movie: "discover/movie"
            case .tv: "discover/tv"
        }
    }
}

/// Query items for `/discover/movie` and `/discover/tv`. Date windows are calendar days in UTC.
enum DiscoverQuery {
    static func items(
        kind: DiscoverKind,
        sort: BrowseSort,
        window: BrowseWindow,
        page: Int,
        locale: Locale,
        today: Date,
        timeZone: TimeZone = .current,
        genreIDs: [Int] = []
    ) -> [URLQueryItem] {
        var extra = [
            URLQueryItem(name: "sort_by", value: sortBy(kind: kind, sort: sort)),
        ]
        if sort == .topRated {
            extra.append(URLQueryItem(name: "vote_count.gte", value: "50"))
        }
        if !genreIDs.isEmpty {
            extra.append(
                URLQueryItem(name: "with_genres", value: genreIDs.map(String.init).joined(separator: "|"))
            )
        }
        extra.append(contentsOf: dateItems(kind: kind, window: window, today: today, timeZone: timeZone))
        return TMDBLocale.queryItems(locale: locale, page: page, extra: extra)
    }

    static func sortBy(kind: DiscoverKind, sort: BrowseSort) -> String {
        switch (kind, sort) {
            case (_, .popular):
                "popularity.desc"
            case (_, .topRated):
                "vote_average.desc"
            case (.movie, .alphabetical):
                "title.asc"
            case (.tv, .alphabetical):
                "name.asc"
            case (.movie, .newest):
                "primary_release_date.desc"
            case (.tv, .newest):
                "first_air_date.desc"
            case (.movie, .oldest):
                "primary_release_date.asc"
            case (.tv, .oldest):
                "first_air_date.asc"
        }
    }

    /// Discover is the All window, which has no date filter. Now Playing and Upcoming
    /// are separate endpoints, except upcoming TV, which Discover filters by first air date.
    static func dateItems(
        kind: DiscoverKind,
        window: BrowseWindow,
        today: Date,
        timeZone: TimeZone = .current
    ) -> [URLQueryItem] {
        guard kind == .tv, window == .upcoming else { return [] }
        let after = TMDBDay.string(
            from: TMDBDay.adding(days: 1, to: today, timeZone: timeZone),
            timeZone: timeZone
        )
        return [URLQueryItem(name: "first_air_date.gte", value: after)]
    }
}

/// A movie or series row before genre names are resolved. Identity is media plus id.
struct BrowseCandidate: Sendable, Equatable {
    enum Media: Sendable, Equatable {
        case movie
        case tv
    }

    let media: Media
    let id: Int
    let title: String
    let posterPath: String?
    let genreIDs: [Int]
    let date: Date?
    let voteAverage: Double
    /// TMDB popularity. The Popular sort uses it when merging movies with TV.
    var popularity: Double = 0

    var identity: String {
        switch media {
            case .movie: "movie-\(id)"
            case .tv: "tv-\(id)"
        }
    }

    static func movie(_ movie: Movie) -> BrowseCandidate {
        BrowseCandidate(
            media: .movie,
            id: movie.id,
            title: movie.title,
            posterPath: movie.posterPath,
            genreIDs: movie.genreIDs,
            date: movie.releaseDate,
            voteAverage: movie.voteAverage,
            popularity: movie.popularity
        )
    }

    static func series(_ series: TVSeriesSummary) -> BrowseCandidate {
        BrowseCandidate(
            media: .tv,
            id: series.id,
            title: series.name,
            posterPath: series.posterPath,
            genreIDs: series.genreIDs,
            date: series.firstAirDate,
            voteAverage: series.voteAverage,
            popularity: series.popularity
        )
    }
}

/// Whether `lhs` should appear above `rhs` for the active sort.
/// Equal keys break A to Z, then by id. A missing date is older than every real date.
enum BrowseOrdering {
    static func comesBefore(_ lhs: BrowseCandidate, _ rhs: BrowseCandidate, sort: BrowseSort) -> Bool {
        switch sort {
            case .popular:
                if lhs.popularity != rhs.popularity {
                return lhs.popularity > rhs.popularity
                }
            case .topRated:
                if lhs.voteAverage != rhs.voteAverage {
                return lhs.voteAverage > rhs.voteAverage
                }
            case .alphabetical:
                break
            case .newest:
                switch (lhs.date, rhs.date) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            case .oldest:
                switch (lhs.date, rhs.date) {
            case let (left?, right?) where left != right:
                return left < right
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            default:
                break
            }
        }
        let titleOrder = lhs.title.compare(
            rhs.title,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.media == .movie && rhs.media == .tv
    }
}

/// Streaming merge of two sorted Discover pages. `consume` only appends.
struct BrowseMerge: Equatable, Sendable {
    var movies: [BrowseCandidate] = []
    var shows: [BrowseCandidate] = []
    var movieCursor = 0
    var showCursor = 0
    var shown: [BrowseCandidate] = []
    /// Popular alternates movie, then show. Other sorts compare a shared key.
    var nextIsMovie = true

    mutating func reset() {
        movies = []
        shows = []
        movieCursor = 0
        showCursor = 0
        shown = []
        nextIsMovie = true
    }

    /// Newly appended ids. Zero means the page was only duplicates.
    @discardableResult
    mutating func appendMovies(_ page: [BrowseCandidate]) -> Int {
        let existing = Set(movies.map(\.id))
        let fresh = page.filter { !existing.contains($0.id) }
        movies.append(contentsOf: fresh)
        return fresh.count
    }

    /// Newly appended ids. Zero means the page was only duplicates.
    @discardableResult
    mutating func appendShows(_ page: [BrowseCandidate]) -> Int {
        let existing = Set(shows.map(\.id))
        let fresh = page.filter { !existing.contains($0.id) }
        shows.append(contentsOf: fresh)
        return fresh.count
    }

    /// Pulls every row that can be decided from the buffers already fetched.
    /// Stops when the next row might still arrive on a later page of the other stream.
    mutating func consume(sort: BrowseSort, moviesHaveMore: Bool, showsHaveMore: Bool) {
        while true {
            let movieReady = movieCursor < movies.count
            let showReady = showCursor < shows.count
            if movieReady && showReady {
                if sort == .popular {
                    if nextIsMovie {
                        shown.append(movies[movieCursor])
                        movieCursor += 1
                    } else {
                        shown.append(shows[showCursor])
                        showCursor += 1
                    }
                    nextIsMovie.toggle()
                } else if BrowseOrdering.comesBefore(movies[movieCursor], shows[showCursor], sort: sort) {
                    shown.append(movies[movieCursor])
                    movieCursor += 1
                } else {
                    shown.append(shows[showCursor])
                    showCursor += 1
                }
            } else if movieReady && !showsHaveMore {
                shown.append(movies[movieCursor])
                movieCursor += 1
            } else if showReady && !moviesHaveMore {
                shown.append(shows[showCursor])
                showCursor += 1
            } else {
                return
            }
        }
    }

    var needsMoviePage: Bool {
        movieCursor >= movies.count
    }

    var needsShowPage: Bool {
        showCursor >= shows.count
    }
}

/// Display row for Browse. Genre ids that miss the catalog are already dropped.
struct BrowseRow: Sendable, Equatable, Identifiable {
    let identity: String
    let media: BrowseCandidate.Media
    let mediaID: Int
    let title: String
    let posterPath: String?
    let genreNames: [String]
    let formattedDate: String
    let date: Date?
    let voteAverage: Double
    let genreIDs: [Int]
    /// TMDB popularity copied onto a list entry. Zero when the payload omitted it.
    var popularity: Double = 0
    /// Personal score, when this title has one. Nil until the list reads annotations.
    var formattedUserScore: String?
    /// Day that score was chosen.
    var formattedRatedOn: String?

    var id: String { identity }

    var genreLine: String {
        genreNames.joined(separator: ", ")
    }

    init(candidate: BrowseCandidate, locale: Locale = .current) {
        identity = candidate.identity
        media = candidate.media
        mediaID = candidate.id
        title = candidate.title
        posterPath = candidate.posterPath
        switch candidate.media {
            case .movie:
                genreNames = MovieGenreCatalog.names(for: candidate.genreIDs)
            case .tv:
                genreNames = TVGenreCatalog.names(for: candidate.genreIDs)
        }
        formattedDate = DisplayDate.day(candidate.date, locale: locale)
        date = candidate.date
        voteAverage = candidate.voteAverage
        genreIDs = candidate.genreIDs
        popularity = candidate.popularity
        formattedUserScore = nil
        formattedRatedOn = nil
    }

    func withUserScore(_ saved: SavedUserScore?) -> BrowseRow {
        var copy = self
        copy.formattedUserScore = saved?.formatted
        copy.formattedRatedOn = saved?.ratedOn
        return copy
    }

    func asMovie() -> Movie {
        Movie(
            id: mediaID,
            title: title,
            posterPath: posterPath,
            releaseDate: date,
            voteAverage: voteAverage,
            genreIDs: genreIDs,
            popularity: popularity
        )
    }
}
