//
//  TVSeriesViewModel.swift
//  TheSilverScreen
//

import Foundation

struct TVSeriesContent: Sendable, Equatable {
    struct SeasonRow: Sendable, Equatable, Identifiable {
        let id: Int
        let name: String
        let seasonNumber: Int
        let episodeCountText: String
        let formattedAirDate: String
        let posterPath: String?
    }

    struct RecommendationRow: Sendable, Equatable, Identifiable {
        let id: Int
        let name: String
        let posterPath: String?
    }

    struct ReviewsSection: Sendable, Equatable {
        let items: [MovieReview]
        let nextPage: Int
        let hasMore: Bool
        let totalCount: Int
        let isLoadingPage: Bool
        let pageError: AppError?
    }

    let detail: TVSeriesDetail
    /// `2 Seasons · Drama · 2008 - 2013` under the title. Empty when every part is missing.
    let heroMetadataLine: String
    let heroMetadataAccessibilityLabel: String
    let formattedRating: String
    let ratingAccessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let userNote: String?
    let formattedRatedOn: String?
    let formattedNotedOn: String?
    let seasons: [SeasonRow]
    let recommendations: [RecommendationRow]
    let reviews: ReviewsSection?
    var fullscreenImages: FullscreenImages?
}

/// Series detail reached from a person's credits or a recommendation.
@Observable
@MainActor
final class TVSeriesViewModel {
    private(set) var state: LoadState<TVSeriesContent> = .idle
    /// Prizes stored on this series, newest ceremony first. The section is hidden when empty.
    private(set) var awardRows: [AwardRow] = []
    /// `Next up: S·E·title` while the series is in progress; nil when unknown or finished.
    private(set) var nextUpSubtitle: String?
    /// Fully watched regular seasons — drives the seasons-carousel eye badge.
    private(set) var watchedSeasonNumbers: Set<Int> = []
    /// Personal season scores for the carousel rating badge, keyed by season number.
    private(set) var seasonScores: [Int: String] = [:]
    /// Personal series scores for the recommendations carousel badge, keyed by series id.
    private(set) var recommendationScores: [Int: String] = [:]

    private let seriesID: Int
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let lists: ListsRepository
    private let tvWatch: TVWatchRepository?
    private let awards: AwardsRepository

    init(
        seriesID: Int,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        lists: ListsRepository,
        tvWatch: TVWatchRepository? = nil,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.seriesID = seriesID
        self.shows = shows
        self.annotations = annotations
        self.lists = lists
        self.tvWatch = tvWatch
        self.awards = awards
    }

    /// Episodes that would be newly marked if the whole series is marked watched.
    func unmarkedEpisodeCountForSeries() async -> Int {
        guard case .loaded(let content, _) = state, let tvWatch else { return 0 }
        do {
            return try await tvWatch.unmarkedEpisodeCount(
                seriesID: seriesID,
                seasons: content.detail.seasons
            )
        } catch {
            return 0
        }
    }

    func load() async {
        state = .loading
        do {
            let detail = try await shows.series(id: seriesID)
            let reviews = await Self.loadReviews(seriesID: seriesID, shows: shows)
            let personal = try await personalDetail()
            awardRows = await awards.seriesAwards(seriesID: seriesID)
            state = .loaded(
                Self.makeContent(detail: detail, reviews: reviews, personal: personal.detail),
                activity: personal.activity
            )
            await reloadWatchProgress(seasons: detail.seasons)
            await enrichListSnapshots(detail.listItem())
        } catch is CancellationError {
            return
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    func retry() async {
        await load()
    }

    /// Reloads Next up and seasons-carousel watch/rating badges (e.g. after popping back).
    func reloadNextUp() async {
        guard case .loaded(let content, _) = state else { return }
        await reloadWatchProgress(seasons: content.detail.seasons)
    }

    private func reloadWatchProgress(seasons: [TVSeasonSummary]) async {
        await reloadNextUpLine(seasons: seasons)
        await reloadSeasonBadges(seasons: seasons)
        if case .loaded(let content, _) = state {
            await reloadRecommendationScores(content)
        }
    }

    private func reloadRecommendationScores(_ content: TVSeriesContent) async {
        let scores = await annotations.formattedScores()
        var map: [Int: String] = [:]
        for row in content.recommendations {
            if let formatted = scores[.series(row.id)]?.formatted {
                map[row.id] = formatted
            }
        }
        recommendationScores = map
    }

    private func reloadNextUpLine(seasons: [TVSeasonSummary]) async {
        guard let tvWatch else {
            nextUpSubtitle = nil
            return
        }
        do {
            let watchState = try await tvWatch.syncNextUp(seriesID: seriesID, seasons: seasons)
            nextUpSubtitle = watchState?.progressSubtitle
        } catch {
            nextUpSubtitle = nil
        }
    }

    private func reloadSeasonBadges(seasons: [TVSeasonSummary]) async {
        let scores = await annotations.formattedScores()
        var scoreMap: [Int: String] = [:]
        for season in seasons where season.seasonNumber > 0 {
            let key = AnnotationKey.season(seriesID: seriesID, seasonNumber: season.seasonNumber)
            if let formatted = scores[key]?.formatted {
                scoreMap[season.seasonNumber] = formatted
            }
        }
        seasonScores = scoreMap

        guard let tvWatch else {
            watchedSeasonNumbers = []
            return
        }
        do {
            let watchState = try await tvWatch.state(seriesID: seriesID)
                ?? TVSeriesWatchState(seriesID: seriesID)
            watchedSeasonNumbers = Set(
                seasons.compactMap { season in
                    guard season.seasonNumber > 0,
                          watchState.isSeasonComplete(
                            seasonNumber: season.seasonNumber,
                            episodeCount: season.episodeCount
                          ) else {
                        return nil
                    }
                    return season.seasonNumber
                }
            )
        } catch {
            watchedSeasonNumbers = []
        }
    }

    /// Saves a half-point score and marks the series watched (completes every episode).
    /// Callers must confirm when `unmarkedEpisodeCountForSeries()` is greater than zero.
    @discardableResult
    func saveUserScore(_ score: Double) async -> TVWatchOutcome? {
        guard case .loaded(let content, _) = state else { return nil }
        do {
            let saved = try await annotations.saveScore(score, for: .series(seriesID))
            apply(PersonalDetail(annotation: saved))
            guard let tvWatch else { return nil }
            let outcome = try await tvWatch.markSeries(
                seriesID: seriesID,
                seasons: content.detail.seasons,
                draft: content.detail.listItem()
            )
            await reloadWatchProgress(seasons: content.detail.seasons)
            return outcome
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
            let saved = try await annotations.saveNote(note, for: .series(seriesID))
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
            let saved = try await annotations.deleteNote(for: .series(seriesID))
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
            let record = try await annotations.annotation(for: .series(seriesID))
            return (PersonalDetail(annotation: record), .none)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (.empty, .failed(.persistence))
        }
    }

    /// Refresh keeps the note and score already on screen when the annotations file cannot be read.
    private func personalKeeping(_ current: TVSeriesContent) async throws -> (detail: PersonalDetail, activity: LoadActivity) {
        do {
            let record = try await annotations.annotation(for: .series(seriesID))
            return (PersonalDetail(annotation: record), .none)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (current.personal, .failed(.persistence))
        }
    }

    private func apply(_ personal: PersonalDetail) {
        guard case .loaded(let content, let activity) = state else { return }
        state = .loaded(content.withPersonal(personal), activity: AnnotationActivity.afterSuccess(activity))
    }

    func noteListSaveFailed() {
        markPersistenceFailure()
    }

    /// Backfills Watched/Watchlist rows that were saved without a poster or other snapshot fields.
    private func enrichListSnapshots(_ draft: ListItemDraft) async {
        do {
            try await lists.enrich(draft: draft)
        } catch is CancellationError {
            return
        } catch {
            // Soft failure: the detail on screen is still good; list art stays sparse until next visit.
        }
    }

    private func markPersistenceFailure() {
        guard case .loaded(let content, _) = state else { return }
        state = .loaded(content, activity: .failed(.persistence))
    }

    /// Pull to refresh. The series already on screen stays up if the request fails.
    func refresh() async {
        guard case .loaded(let current, _) = state else {
            await load()
            return
        }
        state = .loaded(current, activity: .refreshing)
        do {
            let detail = try await shows.series(id: seriesID)
            let reviews = await Self.loadReviews(seriesID: seriesID, shows: shows)
            let personal = try await personalKeeping(current)
            awardRows = await awards.seriesAwards(seriesID: seriesID)
            state = .loaded(
                Self.makeContent(detail: detail, reviews: reviews, personal: personal.detail),
                activity: personal.activity
            )
            await reloadWatchProgress(seasons: detail.seasons)
        } catch is CancellationError {
            state = .loaded(current, activity: .none)
        } catch let error as AppError {
            state = .loaded(current, activity: .failed(error))
        } catch {
            state = .loaded(current, activity: .failed(.unknown))
        }
    }

    func openImages(initialID: String) {
        guard case .loaded(var content, let activity) = state, !content.detail.images.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: initialID,
            images: content.detail.images,
            kind: .backdrop
        )
        state = .loaded(content, activity: activity)
    }

    func dismissImages() {
        guard case .loaded(var content, let activity) = state else { return }
        content.fullscreenImages = nil
        state = .loaded(content, activity: activity)
    }

    /// Opens the series poster. A missing path leaves the screen as it is.
    func openPoster() {
        guard case .loaded(var content, let activity) = state,
              let path = content.detail.posterPath,
              !path.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: path,
            images: [MovieImage(filePath: path, voteAverage: 0)],
            kind: .poster
        )
        state = .loaded(content, activity: activity)
    }

    /// Next review page. Failures keep the reviews already on screen.
    func loadMoreReviews() async {
        guard case .loaded(let content, let activity) = state,
              let reviews = content.reviews,
              reviews.hasMore,
              !reviews.isLoadingPage else { return }

        state = .loaded(
            content.replacing(reviews: reviews.copy(isLoadingPage: true, pageError: nil)),
            activity: activity
        )

        do {
            let page = try await shows.reviews(seriesID: seriesID, page: reviews.nextPage)
            var seen = Set(reviews.items.map(\.id))
            var merged = reviews.items
            for review in page.reviews where seen.insert(review.id).inserted {
                merged.append(review)
            }
            guard case .loaded(let latest, let latestActivity) = state else { return }
            state = .loaded(
                latest.replacing(
                    reviews: TVSeriesContent.ReviewsSection(
                        items: merged,
                        nextPage: page.page + 1,
                        hasMore: page.hasMore,
                        totalCount: page.totalCount,
                        isLoadingPage: false,
                        pageError: nil
                    )
                ),
                activity: latestActivity
            )
        } catch is CancellationError {
            guard case .loaded(let latest, let latestActivity) = state,
                  let current = latest.reviews else { return }
            state = .loaded(
                latest.replacing(reviews: current.copy(isLoadingPage: false, pageError: nil)),
                activity: latestActivity
            )
        } catch let error as AppError {
            guard case .loaded(let latest, let latestActivity) = state,
                  let current = latest.reviews else { return }
            state = .loaded(
                latest.replacing(reviews: current.copy(isLoadingPage: false, pageError: error)),
                activity: latestActivity
            )
        } catch {
            guard case .loaded(let latest, let latestActivity) = state,
                  let current = latest.reviews else { return }
            state = .loaded(
                latest.replacing(reviews: current.copy(isLoadingPage: false, pageError: .unknown)),
                activity: latestActivity
            )
        }
    }

    private static func loadReviews(seriesID: Int, shows: TVRepository) async -> TVSeriesContent.ReviewsSection? {
        do {
            let page = try await shows.reviews(seriesID: seriesID, page: 1)
            guard !page.reviews.isEmpty else { return nil }
            return TVSeriesContent.ReviewsSection(
                items: page.reviews,
                nextPage: page.page + 1,
                hasMore: page.hasMore,
                totalCount: page.totalCount,
                isLoadingPage: false,
                pageError: nil
            )
        } catch is CancellationError {
            return nil
        } catch let error as AppError {
            return TVSeriesContent.ReviewsSection(
                items: [],
                nextPage: 1,
                hasMore: false,
                totalCount: 0,
                isLoadingPage: false,
                pageError: error
            )
        } catch {
            return TVSeriesContent.ReviewsSection(
                items: [],
                nextPage: 1,
                hasMore: false,
                totalCount: 0,
                isLoadingPage: false,
                pageError: .unknown
            )
        }
    }

    private static func makeContent(
        detail: TVSeriesDetail,
        reviews: TVSeriesContent.ReviewsSection?,
        personal: PersonalDetail
    ) -> TVSeriesContent {
        let seasons = detail.seasons.map { season in
            TVSeriesContent.SeasonRow(
                id: season.id,
                name: SeasonTitle.display(name: season.name, number: season.seasonNumber),
                seasonNumber: season.seasonNumber,
                episodeCountText: episodeCountText(season.episodeCount),
                formattedAirDate: DisplayDate.day(season.airDate),
                posterPath: season.posterPath
            )
        }
        let recommendations = detail.recommendations.map {
            TVSeriesContent.RecommendationRow(id: $0.id, name: $0.name, posterPath: $0.posterPath)
        }
        let reviewsSection = reviews
        let heroMetadata = formatHeroMetadata(detail: detail)
        return TVSeriesContent(
            detail: detail,
            heroMetadataLine: heroMetadata.line,
            heroMetadataAccessibilityLabel: heroMetadata.accessibility,
            formattedRating: TMDBRating.formatted(detail.voteAverage),
            ratingAccessibilityLabel: TMDBRating.accessibilityLabel(detail.voteAverage),
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            seasons: seasons,
            recommendations: recommendations,
            reviews: reviewsSection,
            fullscreenImages: nil
        )
    }

    private static func episodeCountText(_ count: Int) -> String {
        count == 1 ? "1 episode" : "\(count) episodes"
    }

    /// Season count (excluding specials) · leading genres · first–last air years.
    static func formatHeroMetadata(detail: TVSeriesDetail) -> (line: String, accessibility: String) {
        var visible: [String] = []
        var spoken: [String] = []

        let seasonCount = detail.seasons.filter { $0.seasonNumber > 0 }.count
        if seasonCount > 0 {
            let text = seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons"
            visible.append(text)
            spoken.append(text)
        }

        let leadingGenres = detail.genres.map(\.name).prefix(2).filter { !$0.isEmpty }
        if !leadingGenres.isEmpty {
            let genreText = leadingGenres.joined(separator: ", ")
            visible.append(genreText)
            spoken.append(genreText)
        }

        let firstYear = DisplayDate.year(detail.firstAirDate)
        let lastYear = DisplayDate.year(detail.lastAirDate)
        switch (firstYear, lastYear) {
            case let (first?, last?):
                visible.append("\(first) - \(last)")
                spoken.append("\(first) to \(last)")
            case let (first?, nil):
                visible.append(first)
                spoken.append(first)
            case let (nil, last?):
                visible.append(last)
                spoken.append(last)
            case (nil, nil):
                break
        }

        return (visible.joined(separator: " · "), spoken.joined(separator: ", "))
    }
}

private extension TVSeriesContent {
    var personal: PersonalDetail {
        PersonalDetail(
            formattedUserScore: formattedUserScore,
            userScoreAccessibilityLabel: userScoreAccessibilityLabel,
            userNote: userNote,
            formattedRatedOn: formattedRatedOn,
            formattedNotedOn: formattedNotedOn
        )
    }

    func withPersonal(_ personal: PersonalDetail) -> TVSeriesContent {
        TVSeriesContent(
            detail: detail,
            heroMetadataLine: heroMetadataLine,
            heroMetadataAccessibilityLabel: heroMetadataAccessibilityLabel,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            seasons: seasons,
            recommendations: recommendations,
            reviews: reviews,
            fullscreenImages: fullscreenImages
        )
    }

    func replacing(reviews: ReviewsSection?) -> TVSeriesContent {
        TVSeriesContent(
            detail: detail,
            heroMetadataLine: heroMetadataLine,
            heroMetadataAccessibilityLabel: heroMetadataAccessibilityLabel,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: formattedUserScore,
            userScoreAccessibilityLabel: userScoreAccessibilityLabel,
            userNote: userNote,
            formattedRatedOn: formattedRatedOn,
            formattedNotedOn: formattedNotedOn,
            seasons: seasons,
            recommendations: recommendations,
            reviews: reviews,
            fullscreenImages: fullscreenImages
        )
    }
}

private extension TVSeriesContent.ReviewsSection {
    func copy(isLoadingPage: Bool, pageError: AppError?) -> Self {
        TVSeriesContent.ReviewsSection(
            items: items,
            nextPage: nextPage,
            hasMore: hasMore,
            totalCount: totalCount,
            isLoadingPage: isLoadingPage,
            pageError: pageError
        )
    }
}
