//
//  AwardTitlesViewModel.swift
//  TheSilverScreen
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
    let imagePath: String?
    let artwork: Artwork
    let route: Route
    /// Snapshot for the list button. Nil when the credit cannot be saved.
    let listDraft: ListItemDraft?
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
    private var nextPage = 1
    private var isPaging = false

    init(
        request: AwardTitleRequest,
        awards: AwardsRepository,
        movies: MovieRepository,
        shows: TVRepository,
        annotations: AnnotationsRepository
    ) {
        self.request = request
        self.awards = awards
        self.movies = movies
        self.shows = shows
        self.annotations = annotations
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

    /// Fetches the next page of local credits. Concurrent calls are ignored.
    func loadMore() async {
        guard hasMore, !isPaging else { return }
        guard case .loaded(let current, let activity) = state, activity == .none else { return }
        isPaging = true
        state = .loaded(current, activity: .loadingMore)
        defer { isPaging = false }
        let page = await awards.creditPage(request: request, winners: showingWinners, page: nextPage)
        let rows = await hydrate(page.credits)
        let merged = current + rows.filter { row in !current.contains { $0.id == row.id } }
        hasMore = page.hasMore && merged.count > current.count
        nextPage += 1
        state = merged.isEmpty ? .empty : .loaded(merged)
    }

    private func reload(keepingVisible: Bool) async {
        isPaging = false
        nextPage = 1
        if keepingVisible, case .loaded(let current, _) = state {
            state = .loaded(current, activity: .refreshing)
        } else {
            state = .loading
        }
        let page = await awards.creditPage(request: request, winners: showingWinners, page: 1)
        let rows = await hydrate(page.credits)
        hasMore = page.hasMore
        nextPage = 2
        if rows.isEmpty {
            state = .empty
        } else {
            state = .loaded(rows)
        }
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
        return indexed.sorted { $0.0 < $1.0 }.map(\.1)
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
                    } else {
                        listDraft = fallbackDraft(id: movieID, kind: .movie, title: title)
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
                    } else {
                        listDraft = fallbackDraft(id: seriesID, kind: .tv, title: title)
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
                    } else {
                        listDraft = fallbackDraft(
                            id: seriesID,
                            kind: .tv,
                            title: seriesTitle(work, fallback: title)
                        )
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
                    } else {
                        listDraft = fallbackDraft(
                            id: seriesID,
                            kind: .tv,
                            title: seriesTitle(work, fallback: title)
                        )
                    }
                }
            }
        }
        return AwardTitleRow(
            id: credit.key,
            title: title,
            awardYear: String(credit.year),
            genreLine: genreNames.joined(separator: ", "),
            userScore: scoreKey.flatMap { scores[$0]?.formatted },
            imagePath: imagePath,
            artwork: artwork,
            route: route,
            listDraft: listDraft
        )
    }

    private nonisolated static func seriesTitle(_ work: AwardWork, fallback: String) -> String {
        if let seriesName = work.seriesName, !seriesName.isEmpty { return seriesName }
        return fallback
    }

    private nonisolated static func fallbackDraft(id: Int, kind: ListItemKind, title: String) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: kind,
            title: title,
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
    }
}

