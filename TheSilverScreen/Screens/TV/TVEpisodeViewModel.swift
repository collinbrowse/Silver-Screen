//
//  TVEpisodeViewModel.swift
//  TheSilverScreen
//

import Foundation

struct TVEpisodeContent: Sendable, Equatable {
    let title: String
    let episodeNumberText: String
    let overview: String
    let formattedAirDate: String
    let formattedRating: String
    let ratingAccessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let userNote: String?
    let formattedRatedOn: String?
    let formattedNotedOn: String?
    let stillPath: String?
    let images: [MovieImage]
    let cast: [TVCredit]
    let guestStars: [TVCredit]
    let directorsAndWriters: [TVCredit]
    /// The rest of this season, in episode order. The episode on screen is left out.
    let otherEpisodes: [TVEpisodeSummary]
    let trailers: [MediaTrailer]
    let streamingProviders: [StreamingProvider]
    var fullscreenImages: FullscreenImages?

    /// Stills for the hero. The episode still leads when the gallery does not already include it.
    var heroImages: [MovieImage] {
        guard let stillPath, !stillPath.isEmpty, !images.contains(where: { $0.filePath == stillPath }) else {
            return images
        }
        return [MovieImage(filePath: stillPath, voteAverage: 0)] + images
    }
}

/// One episode, opened from the episode list on a season.
@Observable
@MainActor
final class TVEpisodeViewModel {
    private(set) var state: LoadState<TVEpisodeContent> = .idle
    /// Prizes for this episode, newest ceremony first. The section is hidden when empty.
    private(set) var awardRows: [AwardRow] = []
    /// Series fields for list membership. Filled from the route, or from a series fetch when empty.
    private(set) var seriesSnapshot: SeriesListSnapshot
    private(set) var catalogSeasons: [TVSeasonSummary] = []
    private(set) var isEpisodeCompleted = false

    private let seriesID: Int
    private let seasonNumber: Int
    private let episodeNumber: Int
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let tvWatch: TVWatchRepository?
    private let awards: AwardsRepository

    init(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        seriesSnapshot: SeriesListSnapshot = .empty,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository? = nil,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.seriesSnapshot = seriesSnapshot
        self.shows = shows
        self.annotations = annotations
        self.tvWatch = tvWatch
        self.awards = awards
    }

    func load() async {
        state = .loading
        do {
            async let episodeCall = shows.episode(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
            async let othersCall = otherEpisodes()
            async let providersCall = shows.streamingProviders(seriesID: seriesID)
            async let catalogCall = resolveCatalog()
            let episode = try await episodeCall
            let others = try await othersCall
            let streamingProviders = await providersCall
            let catalog = await catalogCall
            seriesSnapshot = catalog.snapshot
            catalogSeasons = catalog.seasons
            await reloadCompleted()
            let personal = try await personalDetail()
            awardRows = await awards.episodeAwards(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
            state = .loaded(
                Self.makeContent(
                    episode,
                    otherEpisodes: others,
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

    /// Awards deep links arrive without series art; load it once for the membership draft.
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

    private func reloadCompleted() async {
        guard let tvWatch else {
            isEpisodeCompleted = false
            return
        }
        do {
            isEpisodeCompleted = try await tvWatch.isEpisodeCompleted(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
        } catch {
            isEpisodeCompleted = false
        }
    }

    @discardableResult
    func toggleEpisodeWatched(seriesTitle: String) async -> TVWatchOutcome? {
        guard case .loaded(let content, _) = state, let tvWatch else { return nil }
        let draft = seriesSnapshot.listItem(id: seriesID, title: seriesTitle)
        do {
            let outcome: TVWatchOutcome
            if isEpisodeCompleted {
                outcome = try await tvWatch.unmarkEpisode(
                    seriesID: seriesID,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    draft: draft,
                    seasons: catalogSeasons
                )
            } else {
                outcome = try await tvWatch.markEpisode(
                    seriesID: seriesID,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    title: content.title,
                    draft: draft,
                    seasons: catalogSeasons
                )
            }
            await reloadCompleted()
            return outcome
        } catch is CancellationError {
            return nil
        } catch {
            markPersistenceFailure()
            return nil
        }
    }

    func retry() async {
        await load()
    }

    /// Saves a half-point score and marks this episode completed.
    @discardableResult
    func saveUserScore(_ score: Double, seriesTitle: String) async -> TVWatchOutcome? {
        guard case .loaded = state else { return nil }
        do {
            let saved = try await annotations.saveScore(
                score,
                for: .episode(seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            )
            apply(PersonalDetail(annotation: saved))
            if isEpisodeCompleted {
                return nil
            }
            return await toggleEpisodeWatched(seriesTitle: seriesTitle)
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
                for: .episode(seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
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
                for: .episode(seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
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
                for: .episode(seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
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

    /// Reloads the personal score after a toast rating (saved outside this screen).
    /// Reloads the episode eye after toast Undo restores the ledger.
    func reloadEpisodeCompleted() async {
        await reloadCompleted()
    }

    func reloadPersonalFromStore() async {
        guard case .loaded = state else { return }
        do {
            let personal = try await personalDetail()
            apply(personal.detail)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    func noteListSaveFailed() {
        markPersistenceFailure()
    }

    private func markPersistenceFailure() {
        guard case .loaded(let content, _) = state else { return }
        state = .loaded(content, activity: .failed(.persistence))
    }

    func openImages(initialID: String) {
        guard case .loaded(var content, let activity) = state else { return }
        let images = content.heroImages
        guard !images.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: initialID,
            images: images,
            kind: .backdrop
        )
        state = .loaded(content, activity: activity)
    }

    func dismissImages() {
        guard case .loaded(var content, let activity) = state else { return }
        content.fullscreenImages = nil
        state = .loaded(content, activity: activity)
    }

    /// Season list is extra. A failure here leaves the episode on screen with no carousel.
    private func otherEpisodes() async throws -> [TVEpisodeSummary] {
        do {
            let season = try await shows.season(seriesID: seriesID, seasonNumber: seasonNumber)
            return season.episodes.filter { $0.episodeNumber != episodeNumber }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    private static func makeContent(
        _ episode: TVEpisodeDetail,
        otherEpisodes: [TVEpisodeSummary],
        personal: PersonalDetail,
        streamingProviders: [StreamingProvider]
    ) -> TVEpisodeContent {
        TVEpisodeContent(
            title: episode.title,
            episodeNumberText: "Episode \(episode.episodeNumber)",
            overview: episode.overview,
            formattedAirDate: DisplayDate.day(episode.airDate),
            formattedRating: TMDBRating.formatted(episode.voteAverage),
            ratingAccessibilityLabel: TMDBRating.accessibilityLabel(episode.voteAverage),
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            stillPath: episode.stillPath,
            images: episode.images,
            cast: episode.cast,
            guestStars: episode.guestStars,
            directorsAndWriters: episode.directorsAndWriters,
            otherEpisodes: otherEpisodes,
            trailers: episode.trailers,
            streamingProviders: streamingProviders,
            fullscreenImages: nil
        )
    }
}

private extension TVEpisodeContent {
    func withPersonal(_ personal: PersonalDetail) -> TVEpisodeContent {
        TVEpisodeContent(
            title: title,
            episodeNumberText: episodeNumberText,
            overview: overview,
            formattedAirDate: formattedAirDate,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            stillPath: stillPath,
            images: images,
            cast: cast,
            guestStars: guestStars,
            directorsAndWriters: directorsAndWriters,
            otherEpisodes: otherEpisodes,
            trailers: trailers,
            streamingProviders: streamingProviders,
            fullscreenImages: fullscreenImages
        )
    }
}
