//
//  SearchViewModel.swift
//  TheSilverScreen
//
//  Segmented type-ahead search across movies, TV, and people.
//  One query is shared. Each segment keeps the pages it already fetched
//  for that text, so switching segments does not clear the field or refetch.
//

import Foundation

enum SearchScope: String, CaseIterable, Sendable, Equatable {
    case movies
    case tv
    case people

    var title: String {
        switch self {
        case .movies: "Movies"
        case .tv: "TV"
        case .people: "People"
        }
    }
}

enum SearchListing: Sendable, Equatable {
    case movies([CatalogMovieRow])
    case tv([CatalogTVRow])
    case people([CatalogPersonRow])

    var isEmpty: Bool {
        switch self {
        case .movies(let rows): rows.isEmpty
        case .tv(let rows): rows.isEmpty
        case .people(let rows): rows.isEmpty
        }
    }

    func applying(_ scores: [AnnotationKey: SavedUserScore]) -> SearchListing {
        switch self {
        case .movies(let rows):
            .movies(rows.map { $0.withUserScore(scores[.movie($0.id)]) })
        case .tv(let rows):
            .tv(rows.map { $0.withUserScore(scores[.series($0.id)]) })
        case .people:
            self
        }
    }
}

@Observable
@MainActor
final class SearchViewModel {
    /// Queries are sent after the debounce, including a single character.
    var query: String = ""
    var scope: SearchScope = .movies
    private(set) var state: LoadState<SearchListing> = .idle
    private(set) var hasMore = true
    /// The text whose pages are on screen. The view resets scroll when this changes.
    private(set) var committedQuery = ""
    /// True while the field is focused and empty, so the view can show a dismissible placeholder.
    private(set) var showsFocusedPlaceholder = false

    private let movies: MovieRepository
    private let shows: TVRepository
    private let people: PersonRepository
    private let annotations: AnnotationsRepository
    private let sleeper: any Sleeper
    private let locale: Locale

    private var caches: [SearchScope: [String: Bucket]] = [:]
    private var activeKey = ""
    private var isPaging = false
    private var queryGeneration = 0
    private var requestGeneration = 0
    private var requestTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var stashed: LoadState<SearchListing>?

    init(
        movies: MovieRepository,
        shows: TVRepository,
        people: PersonRepository,
        annotations: AnnotationsRepository,
        sleeper: any Sleeper = TaskSleeper(),
        locale: Locale = .current
    ) {
        self.movies = movies
        self.shows = shows
        self.people = people
        self.annotations = annotations
        self.sleeper = sleeper
        self.locale = locale
    }

    var emptyTitle: String {
        if showsFocusedPlaceholder { return "Search" }
        return trimmedQuery.isEmpty ? "Nothing Popular" : "No Results"
    }

    var emptyMessage: String {
        if showsFocusedPlaceholder {
            return "Type a name or genre"
        }
        if trimmedQuery.isEmpty {
            return "Nothing popular is listed for \(scope.title) right now."
        }
        return "No \(scope.title.lowercased()) matches \"\(trimmedQuery)\"."
    }

    func load() async {
        guard case .idle = state else { return }
        await showCachedOrFetch(scope: scope, query: "")
    }

    /// Debounced type-ahead. A newer change cancels the wait already in flight.
    func scheduleQueryChange() {
        debounceTask?.cancel()
        debounceTask = Task { await self.commitQueryChange() }
    }

    func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
        queryGeneration += 1
    }

    /// Debounced type-ahead. Tests inject `NoopSleeper` so this returns without waiting.
    func commitQueryChange() async {
        queryGeneration += 1
        let generation = queryGeneration
        let snapshot = query
        do {
            try await sleeper.sleep(seconds: 0.3)
        } catch is CancellationError {
            return
        } catch {
            return
        }
        guard generation == queryGeneration else { return }
        await submit(query: snapshot)
    }

    /// Applies the query the debounce would submit. Tests call this instead of sleeping.
    func submit(query rawQuery: String? = nil) async {
        let requested = (rawQuery ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        if requested.isEmpty {
            if fieldIsPresented {
                presentFocusedPlaceholder()
                return
            }
            await showCachedOrFetch(scope: scope, query: "")
            return
        }
        await showCachedOrFetch(scope: scope, query: requested)
    }

    /// Segment changes keep the query and show that segment's pages for this text.
    func reloadForScopeChange() async {
        queryGeneration += 1
        await showCachedOrFetch(scope: scope, query: trimmedQuery)
    }

    /// Focusing an empty field hides the list. Dismissing it puts the last results back.
    func setFieldFocused(_ focused: Bool) {
        fieldIsPresented = focused
        if focused, trimmedQuery.isEmpty {
            presentFocusedPlaceholder()
            return
        }
        guard !focused, showsFocusedPlaceholder else { return }
        restoreAfterDismiss()
    }

    func restoreAfterDismiss() {
        showsFocusedPlaceholder = false
        if let stashed {
            state = stashed
            self.stashed = nil
        }
    }

    /// Dismissing the keyboard does not clear the query or the results.
    func keyboardDismissed() {
        if showsFocusedPlaceholder {
            restoreAfterDismiss()
        }
    }

    func retry() async {
        caches[scope]?[activeKey] = nil
        await showCachedOrFetch(scope: scope, query: activeKey)
    }

    func refresh() async {
        caches[scope]?[activeKey] = nil
        await showCachedOrFetch(scope: scope, query: activeKey, keepingVisible: true)
    }

    /// Writes saved scores onto the rows already on screen, including after returning from detail.
    func reloadDisplayedScores() async {
        guard case .loaded(let listing, let activity) = state else { return }
        let scores = await annotations.formattedScores()
        let stamped = listing.applying(scores)
        guard stamped != listing else { return }
        state = .loaded(stamped, activity: activity)
    }

    func noteListSaveFailed() {
        guard case .loaded(let listing, _) = state else { return }
        state = .loaded(listing, activity: .failed(.persistence))
    }

    /// Fetches the next page for the query and segment already on screen.
    /// Concurrent calls are ignored; failures stay on `.loaded`.
    func loadMore() async {
        guard hasMore, !isPaging, !showsFocusedPlaceholder else { return }
        guard case .loaded(let current, let activity) = state, activity == .none else { return }
        guard var bucket = caches[scope]?[activeKey] else { return }

        let token = requestGeneration
        let page = bucket.nextPage
        let key = activeKey
        let scope = scope
        isPaging = true
        state = .loaded(current, activity: .loadingMore)
        defer { isPaging = false }

        do {
            let fetched = try await fetch(scope: scope, query: key, page: page)
            guard token == requestGeneration else { return }
            bucket.listing = appending(fetched.listing, to: bucket.listing, byPopularity: !key.isEmpty)
            bucket.nextPage = fetched.page + 1
            let grew = listingCount(bucket.listing) > listingCount(current)
            bucket.hasMore = fetched.hasMore && grew
            caches[scope]?[key] = bucket
            hasMore = bucket.hasMore
            state = bucket.listing.isEmpty ? .empty : .loaded(bucket.listing)
            await reloadDisplayedScores()
        } catch is CancellationError {
            if token == requestGeneration, let cached = caches[scope]?[key] {
                state = cached.listing.isEmpty ? .empty : .loaded(cached.listing)
            }
        } catch let error as AppError {
            guard token == requestGeneration else { return }
            state = .loaded(bucket.listing, activity: .failed(error))
        } catch {
            guard token == requestGeneration else { return }
            state = .loaded(bucket.listing, activity: .failed(.unknown))
        }
    }

    /// True while the system search field is presented, including when its text is empty.
    private var fieldIsPresented = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hides the list until the field is dismissed. The list underneath is kept for that tap.
    private func presentFocusedPlaceholder() {
        if stashed == nil {
            stashed = state
        }
        showsFocusedPlaceholder = true
        cancelRequest()
        state = .empty
    }

    private struct Bucket {
        var listing: SearchListing
        var nextPage: Int
        var hasMore: Bool
    }

    private func showCachedOrFetch(scope: SearchScope, query: String, keepingVisible: Bool = false) async {
        stashed = nil
        showsFocusedPlaceholder = false
        if let cached = caches[scope]?[query] {
            cancelRequest()
            activeKey = query
            committedQuery = query
            hasMore = cached.hasMore
            state = cached.listing.isEmpty ? .empty : .loaded(cached.listing)
            await reloadDisplayedScores()
            return
        }

        cancelRequest()
        requestGeneration += 1
        let token = requestGeneration
        activeKey = query

        if keepingVisible, case .loaded(let current, _) = state {
            state = .loaded(current, activity: .refreshing)
        } else {
            state = .loading
        }

        let task = Task { @MainActor in
            await self.performFetch(scope: scope, query: query, token: token, keepingVisible: keepingVisible)
        }
        requestTask = task
        await task.value
    }

    private func performFetch(
        scope: SearchScope,
        query: String,
        token: Int,
        keepingVisible: Bool
    ) async {
        do {
            let fetched = try await fetch(scope: scope, query: query, page: 1)
            guard token == requestGeneration, !Task.isCancelled else { return }
            let bucket = Bucket(
                listing: fetched.listing,
                nextPage: fetched.page + 1,
                hasMore: fetched.hasMore
            )
            var scopeCache = caches[scope] ?? [:]
            scopeCache[query] = bucket
            caches[scope] = scopeCache
            activeKey = query
            committedQuery = query
            hasMore = bucket.hasMore
            state = bucket.listing.isEmpty ? .empty : .loaded(bucket.listing)
            await reloadDisplayedScores()
        } catch is CancellationError {
            return
        } catch {
            guard token == requestGeneration else { return }
            let appError = (error as? AppError) ?? .unknown
            if keepingVisible, case .loaded(let current, _) = state {
                state = .loaded(current, activity: .failed(appError))
            } else {
                state = .failed(appError)
            }
        }
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        requestGeneration += 1
    }

    private struct FetchedPage {
        let listing: SearchListing
        let page: Int
        let hasMore: Bool
    }

    private func fetch(scope: SearchScope, query: String, page: Int) async throws -> FetchedPage {
        switch scope {
        case .movies:
            let genres = SearchGenreMatch.movieGenreIDs(matching: query)
            let result = query.isEmpty
                ? try await movies.popular(page: page, locale: locale)
                : genres.isEmpty
                    ? try await movies.searchMovies(query: query, page: page, locale: locale)
                    : try await movies.movies(inGenres: genres, page: page, locale: locale)
            let ordered = query.isEmpty ? result.movies : result.movies.sorted { $0.popularity > $1.popularity }
            return FetchedPage(
                listing: .movies(ordered.map(CatalogMovieRow.init)),
                page: result.page,
                hasMore: result.hasMore
            )
        case .tv:
            let genres = SearchGenreMatch.tvGenreIDs(matching: query)
            let result = query.isEmpty
                ? try await shows.popular(page: page, locale: locale)
                : genres.isEmpty
                    ? try await shows.search(query: query, page: page, locale: locale)
                    : try await shows.series(inGenres: genres, page: page, locale: locale)
            let ordered = query.isEmpty ? result.series : result.series.sorted { $0.popularity > $1.popularity }
            return FetchedPage(
                listing: .tv(ordered.map(CatalogTVRow.init)),
                page: result.page,
                hasMore: result.hasMore
            )
        case .people:
            let result = query.isEmpty
                ? try await people.popular(page: page, locale: locale)
                : try await people.search(query: query, page: page, locale: locale)
            let ordered = query.isEmpty ? result.people : result.people.sorted { $0.popularity > $1.popularity }
            return FetchedPage(
                listing: .people(ordered.map(CatalogPersonRow.init)),
                page: result.page,
                hasMore: result.hasMore
            )
        }
    }

    private func listingCount(_ listing: SearchListing) -> Int {
        switch listing {
        case .movies(let rows): rows.count
        case .tv(let rows): rows.count
        case .people(let rows): rows.count
        }
    }

    private func appending(_ next: SearchListing, to current: SearchListing, byPopularity: Bool) -> SearchListing {
        switch (current, next) {
        case (.movies(let existing), .movies(let incoming)):
            let merged = existing + incoming.filter { row in !existing.contains { $0.id == row.id } }
            return .movies(byPopularity ? merged.sorted { $0.popularity > $1.popularity } : merged)
        case (.tv(let existing), .tv(let incoming)):
            let merged = existing + incoming.filter { row in !existing.contains { $0.id == row.id } }
            return .tv(byPopularity ? merged.sorted { $0.popularity > $1.popularity } : merged)
        case (.people(let existing), .people(let incoming)):
            let merged = existing + incoming.filter { row in !existing.contains { $0.id == row.id } }
            return .people(byPopularity ? merged.sorted { $0.popularity > $1.popularity } : merged)
        default:
            return next
        }
    }
}

/// Genre names the query starts, so "hor" finds Horror and "sci" finds Science Fiction.
enum SearchGenreMatch {
    static func movieGenreIDs(matching query: String) -> [Int] {
        ids(in: MovieGenreCatalog.namesByID, matching: query)
    }

    static func tvGenreIDs(matching query: String) -> [Int] {
        ids(in: TVGenreCatalog.namesByID, matching: query)
    }

    private static func ids(in namesByID: [Int: String], matching query: String) -> [Int] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3 else { return [] }
        return namesByID.compactMap { id, name in
            name.range(of: needle, options: [.caseInsensitive, .anchored]) != nil ? id : nil
        }.sorted()
    }
}
