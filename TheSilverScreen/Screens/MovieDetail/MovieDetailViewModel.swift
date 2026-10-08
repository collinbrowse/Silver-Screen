//
//  MovieDetailViewModel.swift
//  TheSilverScreen
//

import Foundation

@Observable
@MainActor
final class MovieDetailViewModel {
    private(set) var state: LoadState<MovieDetailContent> = .idle
    /// Prizes for this movie, newest ceremony first. The section is hidden when empty.
    private(set) var awardRows: [AwardRow] = []

    private let movieID: Int
    private let movies: MovieRepository
    private let annotations: AnnotationsRepository
    private let lists: ListsRepository
    private let awards: AwardsRepository

    init(
        movieID: Int,
        movies: MovieRepository,
        annotations: AnnotationsRepository,
        lists: ListsRepository,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.movieID = movieID
        self.movies = movies
        self.annotations = annotations
        self.lists = lists
        self.awards = awards
    }

    func load() async {
        state = .loading

        do {
            let detail = try await movies.movieDetail(id: movieID)
            async let collectionSection = Self.loadCollectionSection(
                movieID: movieID,
                detail: detail,
                movies: movies
            )
            async let reviewsSection = Self.loadReviewsSection(
                movieID: movieID,
                movies: movies
            )
            async let personalSection = personalDetail()
            let personal = try await personalSection
            let content = Self.makeContent(
                detail: detail,
                collection: await collectionSection,
                reviews: await reviewsSection,
                personal: personal.detail
            )
            awardRows = await awards.movieAwards(movieID: movieID)
            state = .loaded(content, activity: personal.activity)
            await enrichListSnapshots(detail.listItem())
            if personal.detail.formattedUserScore != nil {
                await ensureOnWatched(detail.listItem(), at: personal.watchedAt ?? Date())
            }
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

    /// Saves a half-point score and puts the movie on Watched.
    /// A score that fails to save keeps the previous score on screen.
    /// Returns the Watched membership change when the score was saved.
    @discardableResult
    func saveUserScore(_ score: Double) async -> MembershipChange? {
        guard case .loaded(let content, _) = state else { return nil }
        do {
            let saved = try await annotations.saveScore(score, for: .movie(movieID))
            apply(PersonalDetail(annotation: saved))
            return try await lists.addToWatched(content.detail.listItem(), at: saved.watchedAt ?? Date())
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
            let saved = try await annotations.saveNote(note, for: .movie(movieID))
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
            let saved = try await annotations.deleteNote(for: .movie(movieID))
            apply(PersonalDetail(annotation: saved))
            return true
        } catch is CancellationError {
            return false
        } catch {
            markPersistenceFailure()
            return false
        }
    }

    private func personalDetail() async throws -> (detail: PersonalDetail, activity: LoadActivity, watchedAt: Date?) {
        do {
            let record = try await annotations.annotation(for: .movie(movieID))
            let watchedAt = record?.score == nil ? nil : record?.watchedAt
            return (PersonalDetail(annotation: record), .none, watchedAt)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (.empty, .failed(.persistence), nil)
        }
    }

    /// A scored movie belongs on Watched. A title already there keeps its row and date.
    private func ensureOnWatched(_ draft: ListItemDraft, at date: Date) async {
        do {
            _ = try await lists.addToWatched(draft, at: date)
        } catch is CancellationError {
            return
        } catch {
            markPersistenceFailure()
        }
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

    func loadMoreReviews() async {
        guard case .loaded(let content, let activity) = state,
              let reviews = content.reviews,
              reviews.hasMore,
              !reviews.isLoadingPage else { return }

        state = .loaded(
            content.replacing(
                reviews: ReviewsPatch(
                    items: reviews.items,
                    nextPage: reviews.nextPage,
                    hasMore: reviews.hasMore,
                    totalCount: reviews.totalCount,
                    isLoadingPage: true,
                    pageError: nil
                )
            ),
            activity: activity
        )

        do {
            let page = try await movies.movieReviews(id: movieID, page: reviews.nextPage)
            var seen = Set(reviews.items.map(\.id))
            var merged = reviews.items
            for review in page.reviews where seen.insert(review.id).inserted {
                merged.append(review)
            }
            guard case .loaded(let latest, let latestActivity) = state else { return }
            state = .loaded(
                latest.replacing(
                    reviews: ReviewsPatch(
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
                latest.replacing(
                    reviews: ReviewsPatch(
                        items: current.items,
                        nextPage: current.nextPage,
                        hasMore: current.hasMore,
                        totalCount: current.totalCount,
                        isLoadingPage: false,
                        pageError: nil
                    )
                ),
                activity: latestActivity
            )
        } catch let error as AppError {
            guard case .loaded(let latest, let latestActivity) = state,
                  let current = latest.reviews else { return }
            state = .loaded(
                latest.replacing(
                    reviews: ReviewsPatch(
                        items: current.items,
                        nextPage: current.nextPage,
                        hasMore: current.hasMore,
                        totalCount: current.totalCount,
                        isLoadingPage: false,
                        pageError: error
                    )
                ),
                activity: latestActivity
            )
        } catch {
            guard case .loaded(let latest, let latestActivity) = state,
                  let current = latest.reviews else { return }
            state = .loaded(
                latest.replacing(
                    reviews: ReviewsPatch(
                        items: current.items,
                        nextPage: current.nextPage,
                        hasMore: current.hasMore,
                        totalCount: current.totalCount,
                        isLoadingPage: false,
                        pageError: .unknown
                    )
                ),
                activity: latestActivity
            )
        }
    }

    // MARK: - Formatting

    static func makeContent(
        detail: MovieDetail,
        collection: MovieDetailContent.CollectionSection? = nil,
        reviews: MovieDetailContent.ReviewsSection? = nil,
        personal: PersonalDetail = .empty
    ) -> MovieDetailContent {
        let budget = formatCurrency(detail.budget)
        let revenue = formatCurrency(detail.revenue)
        let images = detail.images.isEmpty
            ? nil
            : MovieDetailContent.ImagesSection(items: detail.images)
        let cast = detail.cast.isEmpty
            ? nil
            : MovieDetailContent.CastSection(members: detail.cast)
        let crewPeople = MovieRepository.creditedDirectorsAndWriters(from: detail.crew)
        let crew = crewPeople.isEmpty
            ? nil
            : MovieDetailContent.CrewSection(people: crewPeople)
        let similarItems = detail.similar.map { movie in
            MovieDetailContent.SimilarSection.Item(
                movie: movie,
                genreNames: MovieGenreCatalog.names(for: movie.genreIDs),
                formattedReleaseDate: formatReleaseDate(movie.releaseDate)
            )
        }
        let similar = similarItems.isEmpty
            ? nil
            : MovieDetailContent.SimilarSection(items: similarItems)
        let heroMetadata = formatHeroMetadata(
            releaseDate: detail.releaseDate,
            runtimeMinutes: detail.runtimeMinutes,
            genreNames: detail.genres.map(\.name)
        )

        return MovieDetailContent(
            detail: detail,
            formattedRating: TMDBRating.formatted(detail.voteAverage),
            ratingAccessibilityLabel: TMDBRating.accessibilityLabel(detail.voteAverage),
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            formattedBudget: budget.display,
            budgetAccessibilityLabel: budget.accessibility,
            formattedRevenue: revenue.display,
            revenueAccessibilityLabel: revenue.accessibility,
            formattedReleaseDate: formatReleaseDate(detail.releaseDate),
            heroMetadataLine: heroMetadata.line,
            heroMetadataAccessibilityLabel: heroMetadata.accessibility,
            images: images,
            cast: cast,
            crew: crew,
            similar: similar,
            collection: collection,
            reviews: reviews,
            fullscreenImages: nil
        )
    }

    func openImages(initialID: String) {
        guard case .loaded(let content, let activity) = state,
              let images = content.images else { return }
        state = .loaded(
            content.withFullscreen(
                FullscreenImages(initialID: initialID, images: images.items, kind: .backdrop)
            ),
            activity: activity
        )
    }

    func openPoster() {
        guard case .loaded(let content, let activity) = state,
              let path = content.detail.posterPath,
              !path.isEmpty else { return }
        let poster = MovieImage(filePath: path, voteAverage: 0)
        state = .loaded(
            content.withFullscreen(
                FullscreenImages(initialID: path, images: [poster], kind: .poster)
            ),
            activity: activity
        )
    }

    func dismissImages() {
        guard case .loaded(let content, let activity) = state else { return }
        state = .loaded(content.withFullscreen(nil), activity: activity)
    }

    static func formatReleaseDate(_ date: Date?) -> String {
        guard date != nil else { return "Not available" }
        return DisplayDate.day(date)
    }

    /// Year · runtime · up to two leading genres for the line under the title.
    static func formatHeroMetadata(
        releaseDate: Date?,
        runtimeMinutes: Int?,
        genreNames: [String]
    ) -> (line: String, accessibility: String) {
        var visible: [String] = []
        var spoken: [String] = []

        if let year = DisplayDate.year(releaseDate) {
            visible.append(year)
            spoken.append(year)
        }
        if let runtimeMinutes, runtimeMinutes > 0 {
            visible.append("\(runtimeMinutes) mins")
            spoken.append(runtimeMinutes == 1 ? "1 minute" : "\(runtimeMinutes) minutes")
        }
        let leadingGenres = genreNames.prefix(2).filter { !$0.isEmpty }
        if !leadingGenres.isEmpty {
            let genreText = leadingGenres.joined(separator: ", ")
            visible.append(genreText)
            spoken.append(genreText)
        }

        return (visible.joined(separator: " · "), spoken.joined(separator: ", "))
    }

    static func formatCurrency(_ amount: Int) -> (display: String, accessibility: String) {
        guard amount > 0 else {
            return ("Not available", "Not available")
        }

        let accessibility: String
        if let full = fullCurrencyFormatter.string(from: NSNumber(value: amount)) {
            accessibility = full
        } else {
            accessibility = "$\(amount)"
        }

        if amount >= 1_000_000 {
            let millions = Double(amount) / 1_000_000
            return (String(format: "$%.1fM", millions), accessibility)
        }
        if amount >= 1_000 {
            let thousands = Double(amount) / 1_000
            return (String(format: "$%.1fK", thousands), accessibility)
        }
        return (accessibility, accessibility)
    }

    // MARK: - Private

    private static func loadCollectionSection(
        movieID: Int,
        detail: MovieDetail,
        movies: MovieRepository
    ) async -> MovieDetailContent.CollectionSection? {
        guard let ref = detail.collection else { return nil }
        do {
            let collection = try await movies.collection(id: ref.id)
            let others = collection.parts.filter { $0.id != movieID }
            return MovieDetailContent.CollectionSection(
                id: ref.id,
                title: ref.name,
                posterPath: ref.posterPath,
                movies: others
            )
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private static func loadReviewsSection(
        movieID: Int,
        movies: MovieRepository
    ) async -> MovieDetailContent.ReviewsSection? {
        do {
            let page = try await movies.movieReviews(id: movieID, page: 1)
            guard !page.reviews.isEmpty else { return nil }
            return MovieDetailContent.ReviewsSection(
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
            return MovieDetailContent.ReviewsSection(
                items: [],
                nextPage: 1,
                hasMore: false,
                totalCount: 0,
                isLoadingPage: false,
                pageError: error
            )
        } catch {
            return MovieDetailContent.ReviewsSection(
                items: [],
                nextPage: 1,
                hasMore: false,
                totalCount: 0,
                isLoadingPage: false,
                pageError: .unknown
            )
        }
    }

    private static let fullCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct ReviewsPatch {
    let items: [MovieReview]
    let nextPage: Int
    let hasMore: Bool
    let totalCount: Int
    let isLoadingPage: Bool
    let pageError: AppError?
}

private extension MovieDetailContent {
    func copy(
        collection: CollectionSection?? = nil,
        reviews: ReviewsSection?? = nil,
        fullscreenImages: FullscreenImages?? = nil
    ) -> MovieDetailContent {
        MovieDetailContent(
            detail: detail,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: formattedUserScore,
            userScoreAccessibilityLabel: userScoreAccessibilityLabel,
            userNote: userNote,
            formattedRatedOn: formattedRatedOn,
            formattedNotedOn: formattedNotedOn,
            formattedBudget: formattedBudget,
            budgetAccessibilityLabel: budgetAccessibilityLabel,
            formattedRevenue: formattedRevenue,
            revenueAccessibilityLabel: revenueAccessibilityLabel,
            formattedReleaseDate: formattedReleaseDate,
            heroMetadataLine: heroMetadataLine,
            heroMetadataAccessibilityLabel: heroMetadataAccessibilityLabel,
            images: images,
            cast: cast,
            crew: crew,
            similar: similar,
            collection: collection ?? self.collection,
            reviews: reviews ?? self.reviews,
            fullscreenImages: fullscreenImages ?? self.fullscreenImages
        )
    }

    func withPersonal(_ personal: PersonalDetail) -> MovieDetailContent {
        MovieDetailContent(
            detail: detail,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            formattedBudget: formattedBudget,
            budgetAccessibilityLabel: budgetAccessibilityLabel,
            formattedRevenue: formattedRevenue,
            revenueAccessibilityLabel: revenueAccessibilityLabel,
            formattedReleaseDate: formattedReleaseDate,
            heroMetadataLine: heroMetadataLine,
            heroMetadataAccessibilityLabel: heroMetadataAccessibilityLabel,
            images: images,
            cast: cast,
            crew: crew,
            similar: similar,
            collection: collection,
            reviews: reviews,
            fullscreenImages: fullscreenImages
        )
    }

    func withFullscreen(_ fullscreen: FullscreenImages?) -> MovieDetailContent {
        copy(fullscreenImages: .some(fullscreen))
    }

    func replacing(collection: CollectionSection?) -> MovieDetailContent {
        copy(collection: .some(collection))
    }

    func replacing(reviews: ReviewsPatch) -> MovieDetailContent {
        copy(
            reviews: .some(
                ReviewsSection(
                    items: reviews.items,
                    nextPage: reviews.nextPage,
                    hasMore: reviews.hasMore,
                    totalCount: reviews.totalCount,
                    isLoadingPage: reviews.isLoadingPage,
                    pageError: reviews.pageError
                )
            )
        )
    }
}
