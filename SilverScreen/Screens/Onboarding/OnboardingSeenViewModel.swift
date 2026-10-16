//
//  OnboardingSeenViewModel.swift
//  SilverScreen
//
//  "What have you seen?" Every tap saves through the library repositories right
//  away, so Continue and Skip never have pending work to flush.
//

import Foundation

/// The seen-it grid: suggestions or search results, the picks on Watched, and inline scores.
@Observable
@MainActor
final class OnboardingSeenViewModel {
    /// Ratings the header counts toward. A goal only; Continue works at any count.
    static let ratingGoal = 5
    /// Recent Best Picture winners mixed into the suggestions.
    static let bestPictureLimit = 10

    private(set) var suggestions: LoadState<[OnboardingTitle]> = .idle
    private(set) var searchResults: LoadState<[OnboardingTitle]> = .idle
    var searchText = ""
    /// Item keys on Watched, including picks restored from the library.
    private(set) var pickedKeys: Set<String> = []
    /// Item key to half-point score. A pick without an entry is unrated.
    private(set) var scores: [String: Double] = [:]

    private let movies: MovieRepository
    private let shows: TVRepository
    private let lists: ListsRepository
    private let annotations: AnnotationsRepository
    private let tvWatch: TVWatchRepository
    private let awards: AwardsRepository
    private let now: @Sendable () -> Date
    /// Taps on a poster whose save has not finished yet are ignored.
    private var inFlight: Set<String> = []

    init(
        movies: MovieRepository,
        shows: TVRepository,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository,
        awards: AwardsRepository,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.now = now
        self.movies = movies
        self.shows = shows
        self.lists = lists
        self.annotations = annotations
        self.tvWatch = tvWatch
        self.awards = awards
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !trimmedQuery.isEmpty }

    /// The grid on screen: search results while a query is typed, otherwise suggestions.
    var displayed: LoadState<[OnboardingTitle]> {
        isSearching ? searchResults : suggestions
    }

    var ratedCount: Int { scores.count }

    /// "2 of 5 rated", or a done message once the goal is met.
    var goalText: String {
        ratedCount >= Self.ratingGoal
            ? "\(ratedCount) rated. Nice."
            : "\(ratedCount) of \(Self.ratingGoal) rated"
    }

    var goalFraction: Double {
        min(Double(ratedCount) / Double(Self.ratingGoal), 1)
    }

    func isPicked(_ title: OnboardingTitle) -> Bool {
        pickedKeys.contains(title.id)
    }

    func score(for title: OnboardingTitle) -> Double? {
        scores[title.id]
    }

    /// Restores picks already in the library, then fetches every suggestion source at once.
    func load() async {
        guard case .idle = suggestions else { return }
        suggestions = .loading
        await restorePicks()

        async let bestPicture = Self.capture { [self] in try await bestPictureWinners() }
        let today = now()
        async let topMovies = Self.capture { [movies] in
            OnboardingCatalog.titles(
                OnboardingCatalog.released(try await movies.topMovies(page: 1).movies, by: today)
            )
        }
        async let popularShows = Self.capture { [shows] in
            OnboardingCatalog.titles(
                OnboardingCatalog.series(
                    try await shows.popular(page: 1).series,
                    dropping: OnboardingCatalog.dailyTVGenres
                )
            )
        }
        async let popularMovies = Self.capture { [movies] in
            OnboardingCatalog.titles(
                OnboardingCatalog.released(try await movies.popular(page: 1).movies, by: today)
            )
        }
        async let topShows = Self.capture { [shows] in
            OnboardingCatalog.titles(
                OnboardingCatalog.series(
                    try await shows.topRated(page: 1).series,
                    dropping: OnboardingCatalog.dailyTVGenres
                )
            )
        }

        var results = OnboardingSourceResults()
        // Popular TV is global and leans regional, so it takes the last turn in each round.
        for result in await [bestPicture, topMovies, topShows, popularMovies, popularShows] {
            results.append(result)
        }
        if Task.isCancelled {
            suggestions = .idle
            return
        }
        suggestions = results.state()
    }

    /// Retry after a cold failure.
    func reload() async {
        suggestions = .idle
        await load()
    }

    /// Movie and series search for the current text. An empty query clears results.
    func search() async {
        let query = trimmedQuery
        guard !query.isEmpty else {
            searchResults = .idle
            return
        }
        searchResults = .loading
        async let movieResults = Self.capture { [movies] in
            OnboardingCatalog.titles(try await movies.searchMovies(query: query, page: 1).movies)
        }
        async let showResults = Self.capture { [shows] in
            OnboardingCatalog.titles(try await shows.search(query: query, page: 1).series)
        }
        let found = await [movieResults, showResults]
        // A newer query owns the grid now.
        guard !Task.isCancelled, query == trimmedQuery else { return }

        var titles: [OnboardingTitle] = []
        var firstError: AppError?
        for result in found {
            switch result {
                case .success(let page): titles += page
                case .failure(let error): firstError = firstError ?? (error as? AppError) ?? .unknown
            }
        }
        if !titles.isEmpty {
            searchResults = .loaded(titles.sorted { $0.draft.popularity > $1.draft.popularity })
        } else if let firstError, found.allSatisfy({ if case .failure = $0 { true } else { false } }) {
            searchResults = .failed(firstError)
        } else {
            searchResults = .empty
        }
    }

    /// Puts the title on Watched, or takes it back off along with its score.
    /// A series goes through the episode ledger so every episode is completed;
    /// this step is the confirmation, so there is no dialog.
    func toggle(_ title: OnboardingTitle) async {
        guard inFlight.insert(title.id).inserted else { return }
        defer { inFlight.remove(title.id) }

        if pickedKeys.contains(title.id) {
            let priorScore = scores[title.id]
            pickedKeys.remove(title.id)
            scores[title.id] = nil
            do {
                try await removeFromWatched(title)
                if priorScore != nil {
                    try await annotations.clear(for: title.annotationKey)
                }
            } catch {
                pickedKeys.insert(title.id)
                scores[title.id] = priorScore
                noteSaveFailure(error)
            }
        } else {
            pickedKeys.insert(title.id)
            do {
                try await addToWatched(title)
            } catch {
                pickedKeys.remove(title.id)
                noteSaveFailure(error)
            }
        }
    }

    /// Saves a half-point score for a picked title, or clears it when `score` is nil.
    func rate(_ title: OnboardingTitle, score: Double?) async {
        guard pickedKeys.contains(title.id) else { return }
        if let score, !UserScore.isValid(score) { return }
        let prior = scores[title.id]
        guard prior != score else { return }
        scores[title.id] = score
        do {
            if let score {
                try await annotations.saveScore(score, for: title.annotationKey)
            } else {
                try await annotations.clear(for: title.annotationKey)
            }
        } catch {
            scores[title.id] = prior
            noteSaveFailure(error)
        }
    }

    // MARK: - Saves

    private func addToWatched(_ title: OnboardingTitle) async throws {
        switch title.draft.kind {
            case .tv:
                let detail = try await shows.series(id: title.draft.id)
                try await tvWatch.markSeries(
                    seriesID: title.draft.id,
                    seasons: detail.seasons,
                    draft: title.draft
                )
            case .movie, .person:
                // An unrated movie lands on Watched too; a score added later keeps it there.
                _ = try await lists.addToWatched(title.draft)
        }
    }

    private func removeFromWatched(_ title: OnboardingTitle) async throws {
        switch title.draft.kind {
            case .tv:
                _ = try await tvWatch.clearSeries(seriesID: title.draft.id, draft: title.draft)
            case .movie, .person:
                let snapshot = try await lists.snapshot()
                guard let watched = snapshot.list(.watched) else { return }
                _ = try await lists.remove(itemKey: title.id, listID: watched.id)
        }
    }

    /// A failed save keeps the grid and shows the inline banner. Cancellation is silent.
    private func noteSaveFailure(_ error: Error) {
        guard !(error is CancellationError) else { return }
        let appError = (error as? AppError) ?? .persistence
        if isSearching {
            searchResults = Self.flagging(searchResults, with: appError)
        } else {
            suggestions = Self.flagging(suggestions, with: appError)
        }
    }

    private static func flagging(
        _ state: LoadState<[OnboardingTitle]>,
        with error: AppError
    ) -> LoadState<[OnboardingTitle]> {
        guard case .loaded(let titles, _) = state else { return state }
        return .loaded(titles, activity: .failed(error))
    }

    // MARK: - Sources

    /// Watched entries and their scores, so reopening the flow shows earlier picks.
    private func restorePicks() async {
        guard let snapshot = try? await lists.snapshot(),
              let watched = snapshot.list(.watched) else { return }
        let keys = Set(snapshot.entries.filter { $0.listID == watched.id }.map(\.itemKey))
        pickedKeys.formUnion(keys)
        for record in await annotations.saved() {
            guard let score = record.score else { continue }
            let itemKey: String
            switch record.key.kind {
                case .movie: itemKey = ListEntry.itemKey(id: record.key.subjectID, kind: .movie)
                case .tvSeries: itemKey = ListEntry.itemKey(id: record.key.subjectID, kind: .tv)
                case .tvSeason, .tvEpisode: continue
            }
            if keys.contains(itemKey) {
                scores[itemKey] = score
            }
        }
    }

    /// Newest Best Picture winners from the bundled catalog, with posters from TMDB.
    /// Throws only when every lookup failed.
    private func bestPictureWinners() async throws -> [OnboardingTitle] {
        let page = await awards.creditPage(
            request: AwardTitleRequest(family: .academy, category: "Best Picture"),
            winners: true,
            page: 1
        )
        var ids: [Int] = []
        for credit in page.credits {
            guard let id = credit.work?.movieID, !ids.contains(id) else { continue }
            ids.append(id)
            if ids.count == Self.bestPictureLimit { break }
        }
        guard !ids.isEmpty else { return [] }

        let movies = self.movies
        var details: [Int: MovieDetail] = [:]
        var firstError: Error?
        await withTaskGroup(of: (Int, Result<MovieDetail, Error>).self) { group in
            for id in ids {
                group.addTask {
                    do {
                        return (id, .success(try await movies.movieDetail(id: id)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                    case .success(let detail): details[id] = detail
                    case .failure(let error): firstError = firstError ?? error
                }
            }
        }
        if details.isEmpty, let firstError { throw firstError }
        return ids.compactMap { details[$0].map { OnboardingTitle(draft: $0.listItem()) } }
    }

    /// Wraps one source so a failure becomes a value instead of ending the whole load.
    static func capture(
        _ work: @Sendable () async throws -> [OnboardingTitle]
    ) async -> Result<[OnboardingTitle], Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
