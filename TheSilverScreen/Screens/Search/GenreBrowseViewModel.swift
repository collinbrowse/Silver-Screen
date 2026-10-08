//
//  GenreBrowseViewModel.swift
//  TheSilverScreen
//
//  Discover lists for one merged genre. Every fetch uses `/discover` with
//  genre ids; there is no Now Playing or Upcoming on this screen.
//

import Foundation

@Observable
@MainActor
final class GenreBrowseViewModel {
    let genre: MergedGenre

    private(set) var media: MediaTypes = .all
    private(set) var sort: BrowseSort = .popular
    private(set) var state: LoadState<[BrowseRow]> = .idle
    private(set) var hasMore = true
    private(set) var selectionToken = 0

    private let movies: MovieRepository
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let locale: Locale
    private let timeZone: TimeZone
    private let today: @Sendable () -> Date

    private var generation = 0
    private var merge = BrowseMerge()
    private var moviePage = 1
    private var showPage = 1
    private var movieHasMore = true
    private var showHasMore = true
    private var activePagingTicket: Int?
    private var pagingTicket = 0
    private var pagingTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    init(
        genre: MergedGenre,
        movies: MovieRepository,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        today: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.genre = genre
        self.movies = movies
        self.shows = shows
        self.annotations = annotations
        self.locale = locale
        self.timeZone = timeZone
        self.today = today
    }

    func load() async {
        guard case .idle = state else { return }
        await reload(keepVisible: false)
    }

    func retry() async {
        await reload(keepVisible: false)
    }

    func refresh() async {
        await reload(keepVisible: true)
    }

    func setMedia(_ media: MediaTypes) async {
        guard media != self.media else { return }
        self.media = media
        selectionToken += 1
        await reload(keepVisible: false)
    }

    func setSort(_ sort: BrowseSort) async {
        guard sort != self.sort else { return }
        self.sort = sort
        selectionToken += 1
        await reload(keepVisible: false)
    }

    func noteListSaveFailed() {
        guard case .loaded(let rows, _) = state else { return }
        state = .loaded(rows, activity: .failed(.persistence))
    }

    func loadMore() async {
        guard hasMore, activePagingTicket == nil else { return }
        guard case .loaded(_, let activity) = state, activity == .none else { return }

        pagingTicket += 1
        let ticket = pagingTicket
        let token = generation
        activePagingTicket = ticket
        let task = Task { @MainActor in
            await self.fetchMore(token: token)
        }
        pagingTask = task
        await task.value
        if activePagingTicket == ticket {
            activePagingTicket = nil
            pagingTask = nil
        }
    }

    func reloadDisplayedScores() async {
        await stampScores(token: generation)
    }

    private func reload(keepVisible: Bool) async {
        cancelPaging()
        reloadTask?.cancel()
        generation += 1
        let token = generation
        let task = Task { @MainActor in
            await self.performReload(token: token, keepVisible: keepVisible)
        }
        reloadTask = task
        await task.value
    }

    private func performReload(token: Int, keepVisible: Bool) async {
        if Task.isCancelled || token != generation { return }

        let visible = loadedRows
        if keepVisible, let visible {
            state = .loaded(visible, activity: .refreshing)
        } else {
            resetBuffers()
            state = .loading
        }

        do {
            let fresh = try await fetchFirstPages()
            guard token == generation, !Task.isCancelled else { return }
            resetBuffers()
            apply(fresh)
            publish(activity: .none)
            await stampScores(token: token)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            let appError = (error as? AppError) ?? .unknown
            if keepVisible, let visible {
                state = .loaded(visible, activity: .failed(appError))
            } else {
                state = .failed(appError)
            }
        }
    }

    private func fetchMore(token: Int) async {
        guard case .loaded(let current, _) = state else { return }
        state = .loaded(current, activity: .loadingMore)
        do {
            try await fetchNextPages()
            guard token == generation, !Task.isCancelled else { return }
            publish(activity: .none)
            await stampScores(token: token)
        } catch is CancellationError {
            guard token == generation else { return }
            if case .loaded(let rows, _) = state {
                state = .loaded(rows, activity: .none)
            }
        } catch {
            guard token == generation else { return }
            let appError = (error as? AppError) ?? .unknown
            let rows = loadedRows ?? current
            state = .loaded(rows, activity: .failed(appError))
        }
    }

    private struct FreshPages {
        var movies: MoviePage?
        var shows: TVSeriesPage?
    }

    private func fetchFirstPages() async throws -> FreshPages {
        switch media {
            case .movies:
                return FreshPages(movies: try await movieList(page: 1), shows: nil)
            case .tv:
                return FreshPages(movies: nil, shows: try await showList(page: 1))
            case .all:
                async let movieRequest = movieList(page: 1)
                async let showRequest = showList(page: 1)
                return try await FreshPages(movies: movieRequest, shows: showRequest)
        }
    }

    private func fetchNextPages() async throws {
        switch media {
            case .movies:
                guard movieHasMore else { return }
                let page = try await movieList(page: moviePage)
                guard !Task.isCancelled else { throw CancellationError() }
                let added = merge.appendMovies(page.movies.map(BrowseCandidate.movie))
                moviePage = page.page + 1
                movieHasMore = page.hasMore && added > 0
            case .tv:
                guard showHasMore else { return }
                let page = try await showList(page: showPage)
                guard !Task.isCancelled else { throw CancellationError() }
                let added = merge.appendShows(page.series.map(BrowseCandidate.series))
                showPage = page.page + 1
                showHasMore = page.hasMore && added > 0
            case .all:
                let fetchMovies = merge.needsMoviePage && movieHasMore
                let fetchShows = merge.needsShowPage && showHasMore
                if fetchMovies && fetchShows {
                async let movieRequest = movieList(page: moviePage)
                async let showRequest = showList(page: showPage)
                let (movieResult, showResult) = try await (movieRequest, showRequest)
                guard !Task.isCancelled else { throw CancellationError() }
                let moviesAdded = merge.appendMovies(movieResult.movies.map(BrowseCandidate.movie))
                moviePage = movieResult.page + 1
                movieHasMore = movieResult.hasMore && moviesAdded > 0
                let showsAdded = merge.appendShows(showResult.series.map(BrowseCandidate.series))
                showPage = showResult.page + 1
                showHasMore = showResult.hasMore && showsAdded > 0
                } else if fetchMovies {
                let page = try await movieList(page: moviePage)
                guard !Task.isCancelled else { throw CancellationError() }
                let added = merge.appendMovies(page.movies.map(BrowseCandidate.movie))
                moviePage = page.page + 1
                movieHasMore = page.hasMore && added > 0
                } else if fetchShows {
                let page = try await showList(page: showPage)
                guard !Task.isCancelled else { throw CancellationError() }
                let added = merge.appendShows(page.series.map(BrowseCandidate.series))
                showPage = page.page + 1
                showHasMore = page.hasMore && added > 0
                }
                merge.consume(sort: sort, moviesHaveMore: movieHasMore, showsHaveMore: showHasMore)
        }
    }

    private func movieList(page: Int) async throws -> MoviePage {
        try await movies.discover(
            sort: sort,
            window: .all,
            page: page,
            locale: locale,
            today: today(),
            timeZone: timeZone,
            genreIDs: genre.movieGenreIDs
        )
    }

    private func showList(page: Int) async throws -> TVSeriesPage {
        try await shows.discover(
            sort: sort,
            window: .all,
            page: page,
            locale: locale,
            today: today(),
            timeZone: timeZone,
            genreIDs: genre.tvGenreIDs
        )
    }

    private func apply(_ fresh: FreshPages) {
        if let movies = fresh.movies {
            let added = merge.appendMovies(movies.movies.map(BrowseCandidate.movie))
            moviePage = movies.page + 1
            movieHasMore = movies.hasMore && added > 0
        } else {
            movieHasMore = false
        }
        if let shows = fresh.shows {
            let added = merge.appendShows(shows.series.map(BrowseCandidate.series))
            showPage = shows.page + 1
            showHasMore = shows.hasMore && added > 0
        } else {
            showHasMore = false
        }
        if media == .all {
            merge.consume(sort: sort, moviesHaveMore: movieHasMore, showsHaveMore: showHasMore)
        }
    }

    private func stampScores(token: Int) async {
        let scores = await annotations.formattedScores()
        guard token == generation, case .loaded(let rows, let activity) = state else { return }
        let stamped = rows.map { row in
            let key: AnnotationKey = row.media == .movie ? .movie(row.mediaID) : .series(row.mediaID)
            return row.withUserScore(scores[key])
        }
        guard stamped != rows else { return }
        state = .loaded(stamped, activity: activity)
    }

    private func publish(activity: LoadActivity) {
        let rows = currentCandidates.map { BrowseRow(candidate: $0) }
        switch media {
            case .movies:
                hasMore = movieHasMore
            case .tv:
                hasMore = showHasMore
            case .all:
                let moviesOpen = merge.movieCursor < merge.movies.count || movieHasMore
                let showsOpen = merge.showCursor < merge.shows.count || showHasMore
                hasMore = moviesOpen || showsOpen
        }
        if rows.isEmpty {
            state = activity == .none ? .empty : .loaded(rows, activity: activity)
            hasMore = false
        } else {
            state = .loaded(rows, activity: activity)
        }
    }

    private var currentCandidates: [BrowseCandidate] {
        switch media {
            case .movies: merge.movies
            case .tv: merge.shows
            case .all: merge.shown
        }
    }

    private var loadedRows: [BrowseRow]? {
        if case .loaded(let rows, _) = state { return rows }
        return nil
    }

    private func resetBuffers() {
        merge.reset()
        moviePage = 1
        showPage = 1
        movieHasMore = true
        showHasMore = true
    }

    private func cancelPaging() {
        pagingTask?.cancel()
        pagingTask = nil
        activePagingTicket = nil
    }
}
