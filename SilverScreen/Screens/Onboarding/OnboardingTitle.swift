//
//  OnboardingTitle.swift
//  SilverScreen
//
//  One poster in an onboarding grid, and the merge rules that build each grid
//  from several TMDB lists.
//

import Foundation

/// A movie or series shown in an onboarding grid. Identity is the library item key,
/// so the same title from two sources collapses to one poster.
struct OnboardingTitle: Sendable, Hashable, Identifiable {
    let draft: ListItemDraft

    var id: String { draft.itemKey }
    var isSeries: Bool { draft.kind == .tv }

    /// Personal score key for the inline stars: the movie, or the whole series.
    var annotationKey: AnnotationKey {
        isSeries ? .series(draft.id) : .movie(draft.id)
    }

    /// "Dune, movie, 2021" for VoiceOver.
    var accessibilityName: String {
        let kind = isSeries ? "series" : "movie"
        if let releaseDate = draft.releaseDate {
            let year = Calendar(identifier: .gregorian).component(.year, from: releaseDate)
            return "\(draft.title), \(kind), \(year)"
        }
        return "\(draft.title), \(kind)"
    }
}

/// Pure grid building, kept apart from the view models so tests can pin it.
enum OnboardingCatalog {
    /// Most posters a grid shows before the user searches.
    static let gridLimit = 60

    /// Takes one title from each source in turn so movies and shows stay mixed.
    /// Later duplicates are dropped; the first source to offer a title keeps it.
    static func interleave(_ sources: [[OnboardingTitle]], limit: Int = gridLimit) -> [OnboardingTitle] {
        var seen: Set<String> = []
        var merged: [OnboardingTitle] = []
        let depth = sources.map(\.count).max() ?? 0
        for index in 0..<depth {
            for source in sources where index < source.count {
                let title = source[index]
                guard seen.insert(title.id).inserted else { continue }
                merged.append(title)
                if merged.count == limit { return merged }
            }
        }
        return merged
    }

    /// The watchlist grid never offers a title already marked seen.
    static func excluding(_ titles: [OnboardingTitle], keys: Set<String>) -> [OnboardingTitle] {
        titles.filter { !keys.contains($0.id) }
    }

    static func titles(_ movies: [Movie]) -> [OnboardingTitle] {
        movies.map { OnboardingTitle(draft: $0.listItem()) }
    }

    static func titles(_ series: [TVSeriesSummary]) -> [OnboardingTitle] {
        series.map { OnboardingTitle(draft: $0.listItem()) }
    }

    /// News, reality, soap, and talk. Popular TV is full of them, and nobody
    /// marks a nightly show as seen or plans to watch it.
    static let dailyTVGenres: Set<Int> = [10763, 10764, 10766, 10767]

    /// Movies out by `today`. Popular lists include films not released yet.
    static func released(_ movies: [Movie], by today: Date) -> [Movie] {
        movies.filter { movie in
            guard let releaseDate = movie.releaseDate else { return false }
            return releaseDate <= today
        }
    }

    /// Series in none of `genres`.
    static func series(_ series: [TVSeriesSummary], dropping genres: Set<Int>) -> [TVSeriesSummary] {
        series.filter { genres.isDisjoint(with: $0.genreIDs) }
    }

}

extension OnboardingCatalog {
    /// Movie and series search for both grids, most popular first. Fails only
    /// when both searches failed; one failed half still shows the other's results.
    static func search(
        query: String,
        movies: MovieRepository,
        shows: TVRepository
    ) async -> LoadState<[OnboardingTitle]> {
        async let movieResults = OnboardingSeenViewModel.capture {
            titles(try await movies.searchMovies(query: query, page: 1).movies)
        }
        async let showResults = OnboardingSeenViewModel.capture {
            titles(try await shows.search(query: query, page: 1).series)
        }
        let found = await [movieResults, showResults]
        var results: [OnboardingTitle] = []
        var firstError: AppError?
        var failures = 0
        for result in found {
            switch result {
                case .success(let page):
                    results += page
                case .failure(let error):
                    failures += 1
                    firstError = firstError ?? (error as? AppError) ?? .unknown
            }
        }
        if !results.isEmpty {
            return .loaded(results.sorted { $0.draft.popularity > $1.draft.popularity })
        }
        if failures == found.count, let firstError {
            return .failed(firstError)
        }
        return .empty
    }
}

/// Collects several independent TMDB lists. One failed source drops out; only
/// when every source fails does the grid show an error.
struct OnboardingSourceResults {
    private(set) var sources: [[OnboardingTitle]] = []
    private(set) var firstError: AppError?

    mutating func append(_ result: Result<[OnboardingTitle], Error>) {
        switch result {
            case .success(let titles):
                sources.append(titles)
            case .failure(let error):
                if firstError == nil {
                    firstError = (error as? AppError) ?? .unknown
                }
        }
    }

    /// The merged grid. With nothing to show, any failure wins over `.empty` so the
    /// grid offers a retry instead of claiming there are no titles.
    func state(excluding keys: Set<String> = []) -> LoadState<[OnboardingTitle]> {
        // Exclude before the limit so a long pick list cannot shrink the grid.
        let merged = OnboardingCatalog.interleave(
            sources.map { OnboardingCatalog.excluding($0, keys: keys) }
        )
        if !merged.isEmpty { return .loaded(merged) }
        if let firstError { return .failed(firstError) }
        return .empty
    }
}
