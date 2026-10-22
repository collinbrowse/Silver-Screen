//
//  OnboardingWatchlistViewModel.swift
//  SilverScreen
//
//  "What do you want to watch?" New and popular titles, minus everything the
//  seen step put on Watched. A tap adds to or removes from Watchlist.
//

import Foundation

/// The want-to-watch grid and the picks on Watchlist.
@Observable
@MainActor
final class OnboardingWatchlistViewModel {
    private(set) var state: LoadState<[OnboardingTitle]> = .idle
    private(set) var searchResults: LoadState<[OnboardingTitle]> = .idle
    var searchText = ""
    /// Item keys on Watchlist, including ones already there before this step.
    private(set) var pickedKeys: Set<String> = []

    private let movies: MovieRepository
    private let shows: TVRepository
    private let lists: ListsRepository
    /// Fetched once; exclusion is reapplied when the user comes back with new seen picks.
    private var sources: OnboardingSourceResults?
    private var excludedKeys: Set<String> = []
    private var inFlight: Set<String> = []

    init(movies: MovieRepository, shows: TVRepository, lists: ListsRepository) {
        self.movies = movies
        self.shows = shows
        self.lists = lists
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !trimmedQuery.isEmpty }

    /// The grid on screen: search results while a query is typed, otherwise suggestions.
    var displayed: LoadState<[OnboardingTitle]> {
        isSearching ? searchResults : state
    }

    /// Movie and series search, minus the seen picks. An empty query clears results.
    func search() async {
        let query = trimmedQuery
        guard !query.isEmpty else {
            searchResults = .idle
            return
        }
        searchResults = .loading
        let found = await OnboardingCatalog.search(query: query, movies: movies, shows: shows)
        guard !Task.isCancelled, query == trimmedQuery else { return }
        if case .loaded(let titles, _) = found {
            let kept = OnboardingCatalog.excluding(titles, keys: excludedKeys)
            searchResults = kept.isEmpty ? .empty : .loaded(kept)
        } else {
            searchResults = found
        }
    }

    func isPicked(_ title: OnboardingTitle) -> Bool {
        pickedKeys.contains(title.id)
    }

    /// Builds the grid without `excluding` (the seen picks) or anything already on Watched.
    /// The network is read once; later calls only refilter.
    func load(excluding seenKeys: Set<String>) async {
        var excluded = seenKeys
        if let snapshot = try? await lists.snapshot() {
            if let watched = snapshot.list(.watched) {
                excluded.formUnion(snapshot.entries.filter { $0.listID == watched.id }.map(\.itemKey))
            }
            if let watchlist = snapshot.list(.watchlist) {
                pickedKeys.formUnion(snapshot.entries.filter { $0.listID == watchlist.id }.map(\.itemKey))
            }
        }
        excludedKeys = excluded

        if let sources {
            state = sources.state(excluding: excluded)
            return
        }
        state = .loading

        // Upcoming TV is left out: it is tomorrow's premieres worldwide, none with
        // ratings yet. Series lists drop the regional tail below the vote floor.
        async let upcomingMovies = OnboardingSeenViewModel.capture { [movies] in
            OnboardingCatalog.titles(try await movies.upcoming(page: 1).movies)
        }
        async let nowPlaying = OnboardingSeenViewModel.capture { [movies] in
            OnboardingCatalog.titles(try await movies.nowPlaying(page: 1).movies)
        }
        async let onTheAir = OnboardingSeenViewModel.capture { [shows] in
            OnboardingCatalog.titles(Self.knownSeries(try await shows.onTheAir(page: 1).series))
        }
        async let popularMovies = OnboardingSeenViewModel.capture { [movies] in
            OnboardingCatalog.titles(try await movies.popular(page: 1).movies)
        }
        async let popularShows = OnboardingSeenViewModel.capture { [shows] in
            OnboardingCatalog.titles(Self.knownSeries(try await shows.popular(page: 1).series))
        }

        var results = OnboardingSourceResults()
        let fetched = await [upcomingMovies, nowPlaying, onTheAir, popularMovies, popularShows]
        for result in fetched {
            results.append(result)
        }
        if Task.isCancelled {
            state = .idle
            return
        }
        // Keep a cold failure retryable instead of caching nothing.
        if !results.sources.isEmpty {
            sources = results
        }
        state = results.state(excluding: excludedKeys)
    }

    /// No daily shows, and nothing below the watchlist vote floor.
    private nonisolated static func knownSeries(_ series: [TVSeriesSummary]) -> [TVSeriesSummary] {
        OnboardingCatalog.series(
            OnboardingCatalog.series(series, dropping: OnboardingCatalog.dailyTVGenres),
            withAtLeast: OnboardingCatalog.watchlistVoteFloor
        )
    }

    /// Retry after a cold failure.
    func reload() async {
        sources = nil
        await load(excluding: excludedKeys)
    }

    /// Adds the title to Watchlist, or removes it when it is already there.
    func toggle(_ title: OnboardingTitle) async {
        guard inFlight.insert(title.id).inserted else { return }
        defer { inFlight.remove(title.id) }
        let wasPicked = pickedKeys.contains(title.id)
        if wasPicked {
            pickedKeys.remove(title.id)
        } else {
            pickedKeys.insert(title.id)
        }
        do {
            let snapshot = try await lists.snapshot()
            guard let watchlist = snapshot.list(.watchlist) else { throw AppError.persistence }
            if wasPicked {
                _ = try await lists.remove(itemKey: title.id, listID: watchlist.id)
            } else {
                _ = try await lists.add(draft: title.draft, listID: watchlist.id)
            }
        } catch {
            if wasPicked {
                pickedKeys.insert(title.id)
            } else {
                pickedKeys.remove(title.id)
            }
            guard !(error is CancellationError) else { return }
            let appError = (error as? AppError) ?? .persistence
            if isSearching, case .loaded(let titles, _) = searchResults {
                searchResults = .loaded(titles, activity: .failed(appError))
            } else if case .loaded(let titles, _) = state {
                state = .loaded(titles, activity: .failed(appError))
            }
        }
    }
}
