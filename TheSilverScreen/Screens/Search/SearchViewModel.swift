//
//  SearchViewModel.swift
//  TheSilverScreen
//
//  Unified type-ahead across movies, TV, and people. Preview shows the top
//  five of each type; View all interweaves by match then popularity, with
//  optional Movies / TV / People niche and Genre filters.
//

import Foundation

@Observable
@MainActor
final class SearchViewModel {
    /// Queries are sent after the debounce, including a single character.
    var query: String = ""

    private(set) var state: LoadState<SearchContent> = .idle
    private(set) var hasMore = true
    /// The text whose pages are on screen. The view resets scroll when this changes.
    private(set) var committedQuery = ""
    /// True while the field is focused and empty, so the view can show a dismissible placeholder.
    private(set) var showsFocusedPlaceholder = false
    /// View-all niche. Always `.all` during typeahead preview.
    private(set) var typeNiche: SearchTypeNiche = .all
    /// Optional genre filter on View all. Nil during preview.
    private(set) var genreFilter: MergedGenre?

    /// Fixed search-home cards. Empty, unfocused search shows these instead of popular lists.
    var shelves: [AwardShelf] { AwardShelf.home }

    private let movies: MovieRepository
    private let shows: TVRepository
    private let people: PersonRepository
    private let annotations: AnnotationsRepository
    private let awards: AwardsRepository
    private let sleeper: any Sleeper
    private let locale: Locale

    private var caches: [String: QueryCache] = [:]
    private var activeKey = ""
    private var isPaging = false
    private var queryGeneration = 0
    private var requestGeneration = 0
    private var requestTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var stashed: LoadState<SearchContent>?
    /// False until the user opens View all (or submits) for the current query.
    private var showsAllResults = false

    private let previewLimit = 5

    init(
        movies: MovieRepository,
        shows: TVRepository,
        people: PersonRepository,
        annotations: AnnotationsRepository,
        awards: AwardsRepository = AwardsRepository(catalog: .empty),
        sleeper: any Sleeper = TaskSleeper(),
        locale: Locale = .current
    ) {
        self.movies = movies
        self.shows = shows
        self.people = people
        self.annotations = annotations
        self.awards = awards
        self.sleeper = sleeper
        self.locale = locale
    }

    /// Shelves stay up while the field is empty and not showing the focused placeholder.
    var showsAwardShelves: Bool {
        trimmedQuery.isEmpty && !showsFocusedPlaceholder
    }

    /// Movies / TV / People / Genre pills appear only after View all.
    var showsFilterPills: Bool {
        showsAllResults
            && !trimmedQuery.isEmpty
            && !showsFocusedPlaceholder
            && !showsAwardShelves
    }

    var emptyTitle: String {
        if showsFocusedPlaceholder { return "Search" }
        return "No Results"
    }

    var emptyMessage: String {
        if showsFocusedPlaceholder {
            return "Type a name"
        }
        if genreFilter != nil || typeNiche != .all {
            return "No matches for \"\(trimmedQuery)\" with these filters."
        }
        return "No matches for \"\(trimmedQuery)\"."
    }

    func load() async {
        guard case .idle = state else { return }
        state = .empty
        await awards.prepare()
    }

    /// Debounced type-ahead. A newer change cancels the wait already in flight.
    /// Clearing the field returns to shelves, or the focused placeholder, without waiting.
    func scheduleQueryChange() {
        debounceTask?.cancel()
        if trimmedQuery.isEmpty {
            queryGeneration += 1
            debounceTask = nil
            resetFilters()
            if fieldIsPresented {
                presentFocusedPlaceholder()
            } else {
                showShelves()
            }
            return
        }
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
            resetFilters()
            if fieldIsPresented {
                presentFocusedPlaceholder()
                return
            }
            showShelves()
            return
        }
        // Editing the query always returns to the typeahead preview.
        showsAllResults = false
        typeNiche = .all
        genreFilter = nil
        await showCachedOrFetch(query: requested)
    }

    /// Expands the typeahead into the interleaved View-all list.
    func openAllResults() {
        let requested = trimmedQuery
        guard !requested.isEmpty else { return }
        showsAllResults = true
        showsFocusedPlaceholder = false
        stashed = nil
        if let cache = caches[requested] {
            activeKey = requested
            committedQuery = requested
            publish(from: cache)
            return
        }
        Task { await showCachedOrFetch(query: requested) }
    }

    /// Toggles a Movies / TV / People niche. Tapping the selected pill clears back to all.
    func selectTypeNiche(_ niche: SearchTypeNiche) {
        guard showsAllResults else { return }
        if niche == .all || typeNiche == niche {
            typeNiche = .all
        } else {
            typeNiche = niche
        }
        republishFromCache()
    }

    /// Applies or clears the View-all genre filter over the current search hits.
    func selectGenreFilter(_ genre: MergedGenre?) {
        guard showsAllResults else { return }
        genreFilter = genre
        republishFromCache()
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
        if trimmedQuery.isEmpty {
            stashed = nil
            showShelves()
            return
        }
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
        caches[activeKey] = nil
        await showCachedOrFetch(query: activeKey)
    }

    func refresh() async {
        if showsAwardShelves {
            await awards.prepare()
            return
        }
        caches[activeKey] = nil
        await showCachedOrFetch(query: activeKey, keepingVisible: true)
    }

    /// Writes saved scores onto the rows already on screen, including after returning from detail.
    func reloadDisplayedScores() async {
        guard case .loaded(let content, let activity) = state else { return }
        let scores = await annotations.formattedScores()
        let stamped = content.applying(scores)
        guard stamped != content else { return }
        state = .loaded(stamped, activity: activity)
    }

    func noteListSaveFailed() {
        guard case .loaded(let content, _) = state else { return }
        state = .loaded(content, activity: .failed(.persistence))
    }

    /// Fetches the next page for types still in play. Preview does not page.
    /// Concurrent calls are ignored; failures stay on `.loaded`.
    func loadMore() async {
        guard showsAllResults, hasMore, !isPaging, !showsFocusedPlaceholder, !showsAwardShelves else { return }
        guard case .loaded(let current, let activity) = state, activity == .none else { return }
        guard var cache = caches[activeKey] else { return }

        let token = requestGeneration
        let key = activeKey
        isPaging = true
        state = .loaded(current, activity: .loadingMore)
        defer { isPaging = false }

        do {
            let scopes = scopesForPaging(niche: typeNiche)
            for kind in scopes where cache.bucket(for: kind).hasMore {
                let page = cache.bucket(for: kind).nextPage
                let fetched = try await fetch(kind: kind, query: key, page: page)
                guard token == requestGeneration else { return }
                var bucket = cache.bucket(for: kind)
                let before = bucket.items.count
                bucket.items = appending(fetched.items, to: bucket.items)
                bucket.nextPage = fetched.page + 1
                let grew = bucket.items.count > before
                bucket.hasMore = fetched.hasMore && grew
                cache.setBucket(bucket, for: kind)
            }
            guard token == requestGeneration else { return }
            caches[key] = cache
            publish(from: cache)
            await reloadDisplayedScores()
        } catch is CancellationError {
            if token == requestGeneration, let cached = caches[key] {
                publish(from: cached)
            }
        } catch let error as AppError {
            guard token == requestGeneration else { return }
            state = .loaded(displayedContent(from: cache), activity: .failed(error))
        } catch {
            guard token == requestGeneration else { return }
            state = .loaded(displayedContent(from: cache), activity: .failed(.unknown))
        }
    }

    /// True while the system search field is presented, including when its text is empty.
    private var fieldIsPresented = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetFilters() {
        showsAllResults = false
        typeNiche = .all
        genreFilter = nil
    }

    /// Empty, unfocused search. Does not request popular movies, TV, or people.
    private func showShelves() {
        stashed = nil
        showsFocusedPlaceholder = false
        resetFilters()
        cancelRequest()
        activeKey = ""
        committedQuery = ""
        hasMore = false
        state = .empty
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

    private enum SearchMediaKind: CaseIterable {
        case movies, tv, people
    }

    private struct TypeBucket {
        var items: [SearchResultItem]
        var nextPage: Int
        var hasMore: Bool
    }

    private struct QueryCache {
        var movies: TypeBucket
        var tv: TypeBucket
        var people: TypeBucket

        func bucket(for kind: SearchMediaKind) -> TypeBucket {
            switch kind {
                case .movies: movies
                case .tv: tv
                case .people: people
            }
        }

        mutating func setBucket(_ bucket: TypeBucket, for kind: SearchMediaKind) {
            switch kind {
                case .movies: movies = bucket
                case .tv: tv = bucket
                case .people: people = bucket
            }
        }
    }

    private struct FetchedTypePage {
        let items: [SearchResultItem]
        let page: Int
        let hasMore: Bool
    }

    private func showCachedOrFetch(query: String, keepingVisible: Bool = false) async {
        stashed = nil
        showsFocusedPlaceholder = false
        if let cached = caches[query] {
            cancelRequest()
            activeKey = query
            committedQuery = query
            publish(from: cached)
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
            await self.performFetch(query: query, token: token, keepingVisible: keepingVisible)
        }
        requestTask = task
        await task.value
    }

    private func performFetch(query: String, token: Int, keepingVisible: Bool) async {
        do {
            async let moviePage = fetchFirstPage(kind: .movies, query: query, token: token)
            async let tvPage = fetchFirstPage(kind: .tv, query: query, token: token)
            async let peoplePage = fetchFirstPage(kind: .people, query: query, token: token)
            let (movies, tv, people) = try await (moviePage, tvPage, peoplePage)
            guard token == requestGeneration, !Task.isCancelled else { return }

            let cache = QueryCache(
                movies: TypeBucket(items: movies.items, nextPage: movies.page + 1, hasMore: movies.hasMore),
                tv: TypeBucket(items: tv.items, nextPage: tv.page + 1, hasMore: tv.hasMore),
                people: TypeBucket(items: people.items, nextPage: people.page + 1, hasMore: people.hasMore)
            )
            caches[query] = cache
            activeKey = query
            committedQuery = query
            publish(from: cache)
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

    private func fetchFirstPage(kind: SearchMediaKind, query: String, token: Int) async throws -> FetchedTypePage {
        let fetched = try await fetch(kind: kind, query: query, page: 1)
        let ranked = await rankedFirstPage(fetched.items, kind: kind, query: query, token: token)
        return FetchedTypePage(items: ranked, page: fetched.page, hasMore: fetched.hasMore)
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        requestGeneration += 1
    }

    private func republishFromCache() {
        guard let cache = caches[activeKey] else { return }
        publish(from: cache)
    }

    private func publish(from cache: QueryCache) {
        let content = displayedContent(from: cache)
        hasMore = hasMorePages(in: cache)
        state = content.isEmpty ? .empty : .loaded(content)
    }

    private func displayedContent(from cache: QueryCache) -> SearchContent {
        if showsAllResults {
            return .allResults(filteredAllResults(from: cache))
        }
        return .preview(previewSections(from: cache))
    }

    private func previewSections(from cache: QueryCache) -> SearchPreviewSections {
        SearchPreviewSections(
            movies: cache.movies.items.compactMap(\.movieRow).prefix(previewLimit).map { $0 },
            tv: cache.tv.items.compactMap(\.tvRow).prefix(previewLimit).map { $0 },
            people: cache.people.items.compactMap(\.personRow).prefix(previewLimit).map { $0 }
        )
    }

    private func filteredAllResults(from cache: QueryCache) -> [SearchResultItem] {
        let items: [SearchResultItem]
        switch typeNiche {
            case .all:
                items = interweave(
                    cache.movies.items + cache.tv.items + cache.people.items,
                    query: activeKey
                )
            case .movies:
                items = cache.movies.items
            case .tv:
                items = cache.tv.items
            case .people:
                items = cache.people.items
        }
        guard let genre = genreFilter else { return items }
        return items.filter { matchesGenre($0, genre: genre) }
    }

    private func hasMorePages(in cache: QueryCache) -> Bool {
        scopesForPaging(niche: typeNiche).contains { cache.bucket(for: $0).hasMore }
    }

    private func scopesForPaging(niche: SearchTypeNiche) -> [SearchMediaKind] {
        switch niche {
            case .all: SearchMediaKind.allCases
            case .movies: [.movies]
            case .tv: [.tv]
            case .people: [.people]
        }
    }

    private func matchesGenre(_ item: SearchResultItem, genre: MergedGenre) -> Bool {
        switch item {
            case .movie(let row):
                !Set(row.genreIDs).isDisjoint(with: genre.movieGenreIDs)
            case .tv(let row):
                !Set(row.genreIDs).isDisjoint(with: genre.tvGenreIDs)
            case .person:
                false
        }
    }

    /// Ranks close names ahead of other hits. When nothing on the page is close, searches the long words on their own.
    private func rankedFirstPage(
        _ items: [SearchResultItem],
        kind: SearchMediaKind,
        query: String,
        token: Int
    ) async -> [SearchResultItem] {
        let rankedPage = ranked(items, query: query)
        let terms = FuzzyTextMatch.fallbackTokens(in: query)
        guard !terms.isEmpty, !containsMatch(rankedPage, query: query) else {
            return rankedPage
        }
        let extras = await fallbackItems(kind: kind, tokens: terms)
        guard token == requestGeneration, !Task.isCancelled else { return rankedPage }
        let merged = extras.reduce(rankedPage) { current, extra in
            appending(matchingOnly(extra, query: query), to: current)
        }
        return ranked(merged, query: query)
    }

    private func fallbackItems(kind: SearchMediaKind, tokens: [String]) async -> [[SearchResultItem]] {
        switch tokens.count {
            case 0:
                return []
            case 1:
                return [await fallbackListing(kind: kind, query: tokens[0])].compactMap { $0 }
            default:
                async let first = fallbackListing(kind: kind, query: tokens[0])
                async let second = fallbackListing(kind: kind, query: tokens[1])
                let pair = await (first, second)
                return [pair.0, pair.1].compactMap { $0 }
        }
    }

    private func fallbackListing(kind: SearchMediaKind, query: String) async -> [SearchResultItem]? {
        do {
            return try await fetch(kind: kind, query: query, page: 1).items
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private func containsMatch(_ items: [SearchResultItem], query: String) -> Bool {
        items.contains { FuzzyTextMatch.matches(query: query, candidate: $0.displayName) }
    }

    private func matchingOnly(_ items: [SearchResultItem], query: String) -> [SearchResultItem] {
        items.filter { FuzzyTextMatch.matches(query: query, candidate: $0.displayName) }
    }

    /// Close matches first. Inside each group, the higher popularity stays first.
    private func ranked(_ items: [SearchResultItem], query: String) -> [SearchResultItem] {
        items.sorted {
            comesBefore($0.displayName, $0.popularity, $1.displayName, $1.popularity, query: query)
        }
    }

    private func interweave(_ items: [SearchResultItem], query: String) -> [SearchResultItem] {
        ranked(items, query: query)
    }

    private func comesBefore(
        _ lhsName: String,
        _ lhsPopularity: Double,
        _ rhsName: String,
        _ rhsPopularity: Double,
        query: String
    ) -> Bool {
        let lhsMatch = FuzzyTextMatch.matches(query: query, candidate: lhsName)
        let rhsMatch = FuzzyTextMatch.matches(query: query, candidate: rhsName)
        if lhsMatch != rhsMatch { return lhsMatch }
        return lhsPopularity > rhsPopularity
    }

    private func fetch(kind: SearchMediaKind, query: String, page: Int) async throws -> FetchedTypePage {
        switch kind {
            case .movies:
                let result = try await movies.searchMovies(query: query, page: page, locale: locale)
                let items = result.movies
                    .sorted { $0.popularity > $1.popularity }
                    .map { SearchResultItem.movie(CatalogMovieRow(movie: $0)) }
                return FetchedTypePage(items: items, page: result.page, hasMore: result.hasMore)
            case .tv:
                let result = try await shows.search(query: query, page: page, locale: locale)
                let items = result.series
                    .sorted { $0.popularity > $1.popularity }
                    .map { SearchResultItem.tv(CatalogTVRow(series: $0)) }
                return FetchedTypePage(items: items, page: result.page, hasMore: result.hasMore)
            case .people:
                let result = try await people.search(query: query, page: page, locale: locale)
                let items = result.people
                    .sorted { $0.popularity > $1.popularity }
                    .map { SearchResultItem.person(CatalogPersonRow(person: $0)) }
                return FetchedTypePage(items: items, page: result.page, hasMore: result.hasMore)
        }
    }

    private func appending(_ next: [SearchResultItem], to current: [SearchResultItem]) -> [SearchResultItem] {
        let existingIDs = Set(current.map(\.id))
        return current + next.filter { !existingIDs.contains($0.id) }
    }
}

private extension SearchResultItem {
    var movieRow: CatalogMovieRow? {
        if case .movie(let row) = self { return row }
        return nil
    }

    var tvRow: CatalogTVRow? {
        if case .tv(let row) = self { return row }
        return nil
    }

    var personRow: CatalogPersonRow? {
        if case .person(let row) = self { return row }
        return nil
    }
}
