//
//  AwardTitlesViewModel.swift
//  SilverScreen
//
//  Pages the local catalog (newest ceremony first) and fills each page in
//  through the movie and TV repositories. The catalog title stays when a
//  lookup fails, so the list still orders offline.
//

import Foundation

struct AwardTitleRow: Identifiable, Equatable, Sendable {
    enum Artwork: Equatable, Sendable {
        case poster
        case still
    }

    let id: String
    let title: String
    /// Ceremony year, shown on the line directly under the title.
    let awardYear: String
    /// Comma-separated genres. Empty when the lookup did not include them.
    let genreLine: String
    /// Personal score, when this title has one.
    let userScore: String?
    /// In Progress “Next up” line for a TV series with watch progress.
    let nextUp: String?
    let imagePath: String?
    let artwork: Artwork
    let route: Route
    /// Snapshot for the list button. Nil until TMDB hydration succeeds — never a blank draft.
    let listDraft: ListItemDraft?

    /// Media kind chip for the row (Movie or TV).
    var kindLabel: String? {
        switch route {
            case .movieDetail: "Movie"
            case .tvSeries, .tvSeason, .tvEpisode: "TV"
            default: nil
        }
    }

    func withNextUp(_ caption: String?) -> AwardTitleRow {
        AwardTitleRow(
            id: id,
            title: title,
            awardYear: awardYear,
            genreLine: genreLine,
            userScore: userScore,
            nextUp: caption,
            imagePath: imagePath,
            artwork: artwork,
            route: route,
            listDraft: listDraft
        )
    }
}

@Observable
@MainActor
final class AwardTitlesViewModel {
    let request: AwardTitleRequest
    var showingWinners = true
    private(set) var state: LoadState<[AwardTitleRow]> = .idle
    private(set) var hasMore = false

    private let awards: AwardsRepository
    private let movies: MovieRepository
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let tvWatch: TVWatchRepository?
    private var nextPage = 1
    /// Bumped by every reload. A page or reload that finishes under an older generation is
    /// dropped, so a late result cannot overwrite a newer Winners/Nominees selection or move
    /// `nextPage` for it.
    private var generation = 0
    /// Generation of the `loadMore` in flight, if any. Keyed by generation so a stale page
    /// finishing late cannot clear the flag for a newer selection's page.
    private var pagingGeneration: Int?

    init(
        request: AwardTitleRequest,
        awards: AwardsRepository,
        movies: MovieRepository,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository? = nil
    ) {
        self.request = request
        self.awards = awards
        self.movies = movies
        self.shows = shows
        self.annotations = annotations
        self.tvWatch = tvWatch
    }

    var navigationTitle: String { request.navigationTitle }

    var emptyTitle: String { showingWinners ? "No Winners" : "No Nominees" }

    var emptyMessage: String {
        showingWinners
            ? "No winning titles are in this list yet."
            : "No nominated titles are in this list yet."
    }

    func load() async {
        guard case .idle = state else { return }
        await reload(keepingVisible: false)
    }

    func setShowingWinners(_ winners: Bool) async {
        guard winners != showingWinners else { return }
        showingWinners = winners
        await reload(keepingVisible: true)
    }

    /// Fetches the next page of local credits. Concurrent calls for the same selection are
    /// ignored, and a page that lands after the selection changed is discarded.
    func loadMore() async {
        guard hasMore, pagingGeneration != generation else { return }
        guard case .loaded(let current, let activity) = state, activity.allowsLoadMore else { return }
        let token = generation
        pagingGeneration = token
        defer { if pagingGeneration == token { pagingGeneration = nil } }
        state = .loaded(current, activity: .loadingMore)
        let page = await awards.creditPage(request: request, winners: showingWinners, page: nextPage)
        guard token == generation else { return }
        let rows = await hydrate(page.credits)
        guard token == generation else { return }
        let merged = current + rows.filter { row in !current.contains { $0.id == row.id } }
        hasMore = page.hasMore && merged.count > current.count
        nextPage += 1
        state = merged.isEmpty ? .empty : .loaded(merged)
    }

    /// Loads page one for the current selection. Starting a reload makes any page or reload
    /// still in flight stale, so only the newest selection's results reach the screen.
    private func reload(keepingVisible: Bool) async {
        generation += 1
        let token = generation
        nextPage = 1
        if keepingVisible, case .loaded(let current, _) = state {
            state = .loaded(current, activity: .refreshing)
        } else {
            state = .loading
        }
        let page = await awards.creditPage(request: request, winners: showingWinners, page: 1)
        guard token == generation else { return }
        let rows = await hydrate(page.credits)
        guard token == generation else { return }
        hasMore = page.hasMore
        nextPage = 2
        if rows.isEmpty {
            state = .empty
        } else {
            state = .loaded(rows)
        }
    }

    func noteListSaveFailed() {
        guard case .loaded(let rows, _) = state else { return }
        state = .loaded(rows, activity: .failed(.persistence))
    }

    /// Refreshes Next up captions after returning from a detail screen.
    func reloadDisplayedScores() async {
        guard case .loaded(let rows, let activity) = state else { return }
        let stamped = await stampNextUp(rows)
        guard stamped != rows else { return }
        state = .loaded(stamped, activity: activity)
    }

    private func hydrate(_ credits: [AwardCredit]) async -> [AwardTitleRow] {
        let scores = await annotations.formattedScores()
        var indexed: [(Int, AwardTitleRow)] = []
        indexed.reserveCapacity(credits.count)
        await withTaskGroup(of: (Int, AwardTitleRow).self) { group in
            for (index, credit) in credits.enumerated() {
                let movies = movies
                let shows = shows
                group.addTask {
                    let row = await Self.row(for: credit, movies: movies, shows: shows, scores: scores)
                    return (index, row)
                }
            }
            for await pair in group {
                indexed.append(pair)
            }
        }
        let rows = indexed.sorted { $0.0 < $1.0 }.map(\.1)
        return await stampNextUp(rows)
    }

    private func stampNextUp(_ rows: [AwardTitleRow]) async -> [AwardTitleRow] {
        guard let tvWatch else { return rows }
        let seriesIDs = rows.compactMap { row -> Int? in
            guard let draft = row.listDraft, draft.kind == .tv else { return nil }
            return draft.id
        }
        let captions = await tvWatch.progressSubtitles(for: seriesIDs)
        guard !captions.isEmpty else { return rows }
        return rows.map { row in
            guard let draft = row.listDraft, draft.kind == .tv else { return row }
            return row.withNextUp(captions[draft.id])
        }
    }

    private nonisolated static func row(
        for credit: AwardCredit,
        movies: MovieRepository,
        shows: TVRepository,
        scores: [AnnotationKey: SavedUserScore]
    ) async -> AwardTitleRow {
        let route = credit.work?.route(fallbackSeriesName: credit.title) ?? .movieDetail(id: 0)
        var title = credit.title
        var imagePath: String?
        var artwork: AwardTitleRow.Artwork = .poster
        var genreNames: [String] = []
        var listDraft: ListItemDraft?
        var scoreKey: AnnotationKey?
        if let work = credit.work {
            switch work.kind {
                case .movie:
                    if let movieID = work.movieID {
                        scoreKey = .movie(movieID)
                        if let detail = try? await movies.movieDetail(id: movieID) {
                            title = detail.title
                            imagePath = detail.posterPath
                            genreNames = detail.genres.map(\.name)
                            listDraft = detail.listItem()
                        }
                    }
                case .series:
                    if let seriesID = work.seriesID {
                        scoreKey = .series(seriesID)
                        if let detail = try? await shows.series(id: seriesID) {
                            title = detail.name
                            imagePath = detail.posterPath
                            genreNames = detail.genres.map(\.name)
                            listDraft = detail.listItem()
                        }
                    }
                case .season:
                    if let seriesID = work.seriesID, let seasonNumber = work.seasonNumber {
                        scoreKey = .season(seriesID: seriesID, seasonNumber: seasonNumber)
                        if let detail = try? await shows.season(seriesID: seriesID, seasonNumber: seasonNumber) {
                            title = detail.name
                            imagePath = detail.posterPath
                        }
                        if let series = try? await shows.series(id: seriesID) {
                            genreNames = series.genres.map(\.name)
                            listDraft = series.listItem()
                        }
                    }
                case .episode:
                    artwork = .still
                    if let seriesID = work.seriesID,
                       let seasonNumber = work.seasonNumber,
                       let episodeNumber = work.episodeNumber {
                        scoreKey = .episode(
                            seriesID: seriesID,
                            seasonNumber: seasonNumber,
                            episodeNumber: episodeNumber
                        )
                        if let detail = try? await shows.episode(
                            seriesID: seriesID,
                            seasonNumber: seasonNumber,
                            episodeNumber: episodeNumber
                        ) {
                            title = detail.title
                            imagePath = detail.stillPath
                        }
                        if let series = try? await shows.series(id: seriesID) {
                            genreNames = series.genres.map(\.name)
                            listDraft = series.listItem()
                        }
                    }
            }
        }
        return AwardTitleRow(
            id: credit.key,
            title: title,
            awardYear: String(credit.year),
            genreLine: genreNames.prefix(2).joined(separator: ", "),
            userScore: scoreKey.flatMap { scores[$0]?.formatted },
            nextUp: nil,
            imagePath: imagePath,
            artwork: artwork,
            route: route,
            listDraft: listDraft
        )
    }
}
