//
//  TVSeasonViewModel.swift
//  TheSilverScreen
//

import Foundation

struct TVSeasonContent: Sendable, Equatable {
    let seriesName: String
    let displayName: String
    let overview: String
    /// `7 Episodes · 2008` under the title. Empty when every part is missing.
    let heroMetadataLine: String
    let heroMetadataAccessibilityLabel: String
    let formattedRating: String
    let ratingAccessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let userNote: String?
    let formattedRatedOn: String?
    let formattedNotedOn: String?
    let posterPath: String?
    let images: [MovieImage]
    let cast: [TVCredit]
    let directorsAndWriters: [TVCredit]
    let episodes: [TVEpisodeSummary]
    let trailers: [MediaTrailer]
    let streamingProviders: [StreamingProvider]
    var fullscreenImages: FullscreenImages?
}

/// One season, opened from the seasons carousel on a series.
@Observable
@MainActor
final class TVSeasonViewModel {
    private(set) var state: LoadState<TVSeasonContent> = .idle
    /// Prizes for this season, newest ceremony first. The section is hidden when empty.
    private(set) var awardRows: [AwardRow] = []
    /// Series fields for list membership. Filled from the route, or from a series fetch when empty.
    private(set) var seriesSnapshot: SeriesListSnapshot
    /// Catalog seasons for completion checks. Loaded with the series snapshot.
    private(set) var catalogSeasons: [TVSeasonSummary] = []
    /// Episode numbers in this season marked completed.
    private(set) var completedEpisodeNumbers: Set<Int> = []
    /// Personal scores for episodes in this season, keyed by episode number.
    private(set) var episodeScores: [Int: String] = [:]
    /// Series-level `Next up: S·E·title` while in progress; nil when unknown or finished.
    private(set) var nextUpSubtitle: String?

    /// True when every listed episode in this season is completed.
    var isSeasonFullyWatched: Bool {
        guard case .loaded(let content, _) = state, !content.episodes.isEmpty else { return false }
        return content.episodes.allSatisfy { completedEpisodeNumbers.contains($0.episodeNumber) }
    }

    private let seriesID: Int
    private let seriesName: String
    private let seasonNumber: Int
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let tvWatch: TVWatchRepository?
    private let awards: AwardsRepository

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        seriesSnapshot: SeriesListSnapshot = .empty,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository? = nil,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.seriesSnapshot = seriesSnapshot
        self.shows = shows
        self.annotations = annotations
        self.tvWatch = tvWatch
        self.awards = awards
    }

    func load() async {
        state = .loading
        do {
            async let seasonCall = shows.season(seriesID: seriesID, seasonNumber: seasonNumber)
            async let providersCall = shows.streamingProviders(seriesID: seriesID)
            async let catalogCall = resolveCatalog()
            let season = try await seasonCall
            let streamingProviders = await providersCall
            let catalog = await catalogCall
            seriesSnapshot = catalog.snapshot
            catalogSeasons = catalog.seasons
            let personal = try await personalDetail()
            await reloadCompletedEpisodes(from: season.episodes)
            await reloadEpisodeScores(from: season.episodes)
            await reloadNextUp()
            awardRows = await awards.seasonAwards(seriesID: seriesID, seasonNumber: seasonNumber)
            state = .loaded(
                Self.makeContent(
                    season: season,
                    seriesName: seriesName,
                    personal: personal.detail,
                    streamingProviders: streamingProviders
                ),
                activity: personal.activity
            )
        } catch is CancellationError {
            return
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    /// Awards deep links arrive without series art; load seasons for watch completion too.
    private func resolveCatalog() async -> (snapshot: SeriesListSnapshot, seasons: [TVSeasonSummary]) {
        do {
            let detail = try await shows.series(id: seriesID)
            let snapshot = seriesSnapshot.isEmpty ? SeriesListSnapshot(detail: detail) : seriesSnapshot
            return (snapshot, detail.seasons)
        } catch is CancellationError {
            return (seriesSnapshot, catalogSeasons)
        } catch {
            return (seriesSnapshot, catalogSeasons)
        }
    }

    private func reloadCompletedEpisodes(from episodes: [TVEpisodeSummary]) async {
        guard let tvWatch else {
            completedEpisodeNumbers = []
            return
        }
        do {
            let state = try await tvWatch.state(seriesID: seriesID)
            completedEpisodeNumbers = Set(
                episodes.compactMap { episode in
                    state?.contains(seasonNumber: seasonNumber, episodeNumber: episode.episodeNumber) == true
                        ? episode.episodeNumber
                        : nil
                }
            )
        } catch {
            completedEpisodeNumbers = []
        }
    }

    /// Refreshes personal episode scores for the season list (e.g. after a toast rating).
    func reloadEpisodeScores() async {
        guard case .loaded(let content, _) = state else { return }
        await reloadEpisodeScores(from: content.episodes)
    }

    /// Reloads the Next up line after episode / season watch changes.
    func reloadNextUp() async {
        guard let tvWatch else {
            nextUpSubtitle = nil
            return
        }
        do {
            let watchState = try await tvWatch.syncNextUp(
                seriesID: seriesID,
                seasons: catalogSeasons
            )
            nextUpSubtitle = watchState?.progressSubtitle
        } catch {
            nextUpSubtitle = nil
        }
    }

    /// Reloads completed eyes and Next up after toast Undo restores the ledger.
    func reloadWatchChrome() async {
        guard case .loaded(let content, _) = state else { return }
        await reloadCompletedEpisodes(from: content.episodes)
        await reloadNextUp()
    }

    private func reloadEpisodeScores(from episodes: [TVEpisodeSummary]) async {
        let scores = await annotations.formattedScores()
        var mapped: [Int: String] = [:]
        for episode in episodes {
            let key = AnnotationKey.episode(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episode.episodeNumber
            )
            if let formatted = scores[key]?.formatted {
                mapped[episode.episodeNumber] = formatted
            }
        }
        episodeScores = mapped
    }

    func unmarkedEpisodeCountForSeason() async -> Int {
        guard case .loaded(let content, _) = state, let tvWatch else { return 0 }
        do {
            return try await tvWatch.unmarkedEpisodeCount(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeCount: content.episodes.count
            )
        } catch {
            return 0
        }
    }

    @discardableResult
    func toggleEpisodeWatched(_ episode: TVEpisodeSummary) async -> TVWatchOutcome? {
        guard case .loaded = state, let tvWatch else { return nil }
        let draft = seriesSnapshot.listItem(id: seriesID, title: seriesName)
        do {
            let outcome: TVWatchOutcome
            let knownTitles = Dictionary(
                uniqueKeysWithValues: (loadedEpisodes() ?? []).map { row in
                    (
                        TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: row.episodeNumber),
                        row.title
                    )
                }
            )
            if completedEpisodeNumbers.contains(episode.episodeNumber) {
                outcome = try await tvWatch.unmarkEpisode(
                    seriesID: seriesID,
                    seasonNumber: seasonNumber,
                    episodeNumber: episode.episodeNumber,
                    draft: draft,
                    seasons: catalogSeasons
                )
            } else {
                outcome = try await tvWatch.markEpisode(
                    seriesID: seriesID,
                    seasonNumber: seasonNumber,
                    episodeNumber: episode.episodeNumber,
                    title: episode.title,
                    draft: draft,
                    seasons: catalogSeasons,
                    knownTitles: knownTitles
                )
            }
            if let content = loadedEpisodes() {
                await reloadCompletedEpisodes(from: content)
            }
            await reloadNextUp()
            return outcome
        } catch is CancellationError {
            return nil
        } catch {
            markPersistenceFailure()
            return nil
        }
    }

    @discardableResult
    func markSeasonWatched() async -> TVWatchOutcome? {
        guard case .loaded(let content, _) = state, let tvWatch else { return nil }
        let titles = Dictionary(uniqueKeysWithValues: content.episodes.map { ($0.episodeNumber, $0.title) })
        do {
            let outcome = try await tvWatch.markSeason(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeCount: content.episodes.count,
                episodeTitles: titles,
                draft: seriesSnapshot.listItem(id: seriesID, title: seriesName),
                seasons: catalogSeasons
            )
            await reloadCompletedEpisodes(from: content.episodes)
            await reloadNextUp()
            return outcome
        } catch is CancellationError {
            return nil
        } catch {
            markPersistenceFailure()
            return nil
        }
    }

    @discardableResult
    func unmarkSeasonWatched() async -> TVWatchOutcome? {
        guard case .loaded(let content, _) = state, let tvWatch else { return nil }
        do {
            let outcome = try await tvWatch.unmarkSeason(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeCount: content.episodes.count,
                draft: seriesSnapshot.listItem(id: seriesID, title: seriesName),
                seasons: catalogSeasons
            )
            await reloadCompletedEpisodes(from: content.episodes)
            await reloadNextUp()
            return outcome
        } catch is CancellationError {
            return nil
        } catch {
            markPersistenceFailure()
            return nil
        }
    }

    private func loadedEpisodes() -> [TVEpisodeSummary]? {
        guard case .loaded(let content, _) = state else { return nil }
        return content.episodes
    }

    func retry() async {
        await load()
    }

    /// Saves a half-point score and marks this season’s episodes completed.
    /// Callers must confirm when `unmarkedEpisodeCountForSeason()` is greater than zero.
    @discardableResult
    func saveUserScore(_ score: Double) async -> TVWatchOutcome? {
        guard case .loaded = state else { return nil }
        do {
            let saved = try await annotations.saveScore(
                score,
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            apply(PersonalDetail(annotation: saved))
            return await markSeasonWatched()
        } catch is CancellationError {
            return nil
        } catch {
            markPersistenceFailure()
            return nil
        }
    }

    /// Saves a note. Returns false when the write fails so the editor can stay open.
    func saveUserNote(_ note: String) async -> Bool {
        guard case .loaded = state else { return false }
        do {
            let saved = try await annotations.saveNote(
                note,
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            apply(PersonalDetail(annotation: saved))
            return true
        } catch is CancellationError {
            return false
        } catch {
            markPersistenceFailure()
            return false
        }
    }

    /// Removes the note and leaves the score. Returns false when the write fails.
    func deleteUserNote() async -> Bool {
        guard case .loaded = state else { return false }
        do {
            let saved = try await annotations.deleteNote(
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            apply(PersonalDetail(annotation: saved))
            return true
        } catch is CancellationError {
            return false
        } catch {
            markPersistenceFailure()
            return false
        }
    }

    private func personalDetail() async throws -> (detail: PersonalDetail, activity: LoadActivity) {
        do {
            let record = try await annotations.annotation(
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            return (PersonalDetail(annotation: record), .none)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (.empty, .failed(.persistence))
        }
    }

    private func apply(_ personal: PersonalDetail) {
        guard case .loaded(let content, let activity) = state else { return }
        state = .loaded(content.withPersonal(personal), activity: AnnotationActivity.afterSuccess(activity))
    }

    func noteListSaveFailed() {
        markPersistenceFailure()
    }

    private func markPersistenceFailure() {
        guard case .loaded(let content, _) = state else { return }
        state = .loaded(content, activity: .failed(.persistence))
    }

    func openImages(initialID: String) {
        guard case .loaded(var content, let activity) = state, !content.images.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: initialID,
            images: content.images,
            kind: .backdrop
        )
        state = .loaded(content, activity: activity)
    }

    func dismissImages() {
        guard case .loaded(var content, let activity) = state else { return }
        content.fullscreenImages = nil
        state = .loaded(content, activity: activity)
    }

    /// Opens the season poster. A missing path leaves the screen as it is.
    func openPoster() {
        guard case .loaded(var content, let activity) = state,
              let path = content.posterPath,
              !path.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: path,
            images: [MovieImage(filePath: path, voteAverage: 0)],
            kind: .poster
        )
        state = .loaded(content, activity: activity)
    }

    private static func makeContent(
        season: TVSeasonDetail,
        seriesName: String,
        personal: PersonalDetail,
        streamingProviders: [StreamingProvider]
    ) -> TVSeasonContent {
        let heroMetadata = formatHeroMetadata(season: season)
        return TVSeasonContent(
            seriesName: seriesName,
            displayName: SeasonTitle.display(name: season.name, number: season.seasonNumber),
            overview: season.overview,
            heroMetadataLine: heroMetadata.line,
            heroMetadataAccessibilityLabel: heroMetadata.accessibility,
            formattedRating: TMDBRating.formatted(season.voteAverage),
            ratingAccessibilityLabel: TMDBRating.accessibilityLabel(season.voteAverage),
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            posterPath: season.posterPath,
            images: season.images,
            cast: season.cast,
            directorsAndWriters: season.directorsAndWriters,
            episodes: season.episodes,
            trailers: season.trailers,
            streamingProviders: streamingProviders,
            fullscreenImages: nil
        )
    }

    /// Episode count · air year for the line under the season title.
    static func formatHeroMetadata(season: TVSeasonDetail) -> (line: String, accessibility: String) {
        var visible: [String] = []
        var spoken: [String] = []

        let episodeCount = season.episodes.count
        if episodeCount > 0 {
            let text = episodeCount == 1 ? "1 Episode" : "\(episodeCount) Episodes"
            visible.append(text)
            spoken.append(text)
        }
        if let year = DisplayDate.year(season.airDate) {
            visible.append(year)
            spoken.append(year)
        }

        return (visible.joined(separator: " · "), spoken.joined(separator: ", "))
    }
}

private extension TVSeasonContent {
    func withPersonal(_ personal: PersonalDetail) -> TVSeasonContent {
        TVSeasonContent(
            seriesName: seriesName,
            displayName: displayName,
            overview: overview,
            heroMetadataLine: heroMetadataLine,
            heroMetadataAccessibilityLabel: heroMetadataAccessibilityLabel,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            posterPath: posterPath,
            images: images,
            cast: cast,
            directorsAndWriters: directorsAndWriters,
            episodes: episodes,
            trailers: trailers,
            streamingProviders: streamingProviders,
            fullscreenImages: fullscreenImages
        )
    }
}
