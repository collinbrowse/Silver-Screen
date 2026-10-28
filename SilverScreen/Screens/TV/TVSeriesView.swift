//
//  TVSeriesView.swift
//  SilverScreen
//

import SwiftUI

struct TVSeriesView: View {
    @Bindable var viewModel: TVSeriesViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let shows: TVRepository
    let tvWatch: TVWatchRepository
    var router: NavigationRouter?

    @Environment(ListChangeNotice.self) private var notice
    @Namespace private var heroTransition
    @State private var selectedBackdropID: String?
    @State private var playingTrailer: MediaTrailer?
    @State private var loadingTrailerID: String?

    private var fullscreenBinding: Binding<FullscreenImages?> {
        Binding(
            get: {
                if case .loaded(let content, _) = viewModel.state {
                    return content.fullscreenImages
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissImages()
                }
            }
        )
    }

    private var annotationEditorBinding: Binding<AnnotationEditorSession?> {
        Binding(
            get: { viewModel.annotationEditor },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissAnnotationEditor()
                }
            }
        )
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView()
                case .empty:
                    EmptyStateView(
                        title: "Series Unavailable",
                        message: "This series could not be shown.",
                        systemImage: "tv"
                    )
                case .loaded(let content, let activity):
                    loaded(content)
                    .overlay(alignment: .top) {
                        LoadActivityBanner(activity: activity)
                    }
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.retry()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .toolbar {
            if case .loaded(let content, _) = viewModel.state {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    WatchedToggleButton(
                        draft: content.detail.listItem(),
                        lists: lists,
                        index: listsIndex,
                        tvWatch: tvWatch,
                        shows: shows,
                        seasons: content.detail.seasons,
                        chrome: false,
                        isWatchedOverride: viewModel.isSeriesFullyWatched,
                        onToggleComplete: { Task { await viewModel.reloadNextUp() } },
                        onFailure: { viewModel.noteListSaveFailed() }
                    )

                    ListMembershipButton(
                        draft: content.detail.listItem(),
                        lists: lists,
                        index: listsIndex
                    ) {
                        viewModel.noteListSaveFailed()
                    }
                }
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
        .onAppear {
            // Season page (and series eye) write the watch ledger; refresh badges/Next up on return.
            Task { await viewModel.reloadNextUp() }
        }
        .onChange(of: notice.ratingKey) { _, key in
            if key == nil {
                Task { await viewModel.reloadPersonalFromStore() }
            }
        }
        .onChange(of: notice.watchRevision) { _, _ in
            Task { await viewModel.reloadNextUp() }
        }
        .trailerPlayer($playingTrailer, loadingID: $loadingTrailerID)
        .sheet(item: annotationEditorBinding) { session in
            AnnotationEditorSheet(
                title: session.title,
                score: session.score,
                note: session.note,
                canClear: session.canClear,
                onSave: { await viewModel.saveUserAnnotation(score: $0, note: $1) },
                onClear: { await viewModel.clearUserAnnotation() }
            )
        }
        .fullScreenCover(item: fullscreenBinding) { selection in
            FullscreenImageViewer(
                images: selection.images,
                initialID: selection.initialID,
                imageKind: selection.kind,
                imageLoader: imageLoader
            ) {
                viewModel.dismissImages()
            }
            .navigationTransition(.zoom(sourceID: selection.initialID, in: heroTransition))
        }
    }

    private var navigationTitle: String {
        if case .loaded(let content, _) = viewModel.state {
            return content.detail.name
        }
        return ""
    }

    private func loaded(_ content: TVSeriesContent) -> some View {
        ScrollViewReader { proxy in
            seriesScroll(content, scrollTo: { id in
                proxy.scrollTo(id, anchor: .top)
                })
            .tourScrolls(with: proxy)
        }
    }

    private func seriesScroll(_ content: TVSeriesContent, scrollTo: @escaping (String) -> Void) -> some View {
        let bleedsToTop = !content.detail.images.isEmpty
        return DetailPageReader { page in
            ScrollView {
                DetailPageSections(
                    page: page,
                    plan: TVSeriesLayout.plan(for: page.layout, showing: shownSections(content))
                ) { section, slot in
                    sectionView(section, in: slot, layout: page.layout, content: content, scrollTo: scrollTo)
                }
                .padding(.bottom, DesignSpacing.lg)
                .readableColumn(maxWidth: page.layout.columnCap)
                .coordinateSpace(.named("detailScroll"))
            }
            .heroStatusBarBleed(enabled: bleedsToTop)
            .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private func shownSections(_ content: TVSeriesContent) -> Set<TVSeriesLayout.Section> {
        var shown: Set<TVSeriesLayout.Section> = [
            .hero(.all), .hero(.backdrop), .hero(.identity), .ratingAndStoryline,
        ]
        if !viewModel.awardRows.isEmpty { shown.insert(.awards) }
        if !content.seasons.isEmpty || !content.recommendations.isEmpty
            || !content.detail.cast.isEmpty || !content.detail.directorsAndWriters.isEmpty {
            shown.insert(.carousels)
        }
        if content.reviews != nil { shown.insert(.reviews) }
        if !content.detail.streamingProviders.isEmpty { shown.insert(.attribution) }
        return shown
    }

    @ViewBuilder
    private func sectionView(
        _ section: TVSeriesLayout.Section,
        in slot: DetailSlot,
        layout: DetailPageLayout,
        content: TVSeriesContent,
        scrollTo: @escaping (String) -> Void
    ) -> some View {
        switch section {
            case .hero(let part):
                seriesHero(content, layout: layout, part: part)
            case .ratingAndStoryline:
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    TMDBRatingCard(
                        formattedRating: content.formattedRating,
                        accessibilityLabel: content.ratingAccessibilityLabel,
                        formattedUserScore: content.formattedUserScore,
                        userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
                        onEdit: { viewModel.openAnnotationEditor() }
                    )
                    LogWatchButton(title: LogWatchTitle(series: content.detail), currentScore: content.userScore)
                    MediaDescriptionSection(
                        overview: content.detail.overview,
                        note: content.userNote,
                        notedOn: content.formattedNotedOn,
                        onEdit: { viewModel.openAnnotationEditor() },
                        scrollTo: scrollTo
                    )
                }
            case .awards:
                AwardRowsSection(rows: viewModel.awardRows)
            case .carousels:
                carousels(content)
            case .reviews:
                reviews(content, scrollTo: scrollTo, columns: layout.gridColumns(in: slot))
            case .attribution:
                JustWatchAttributionFooter()
        }
    }

    private func seriesHero(_ content: TVSeriesContent, layout: DetailPageLayout, part: DetailHeroPart) -> some View {
        DetailHero(
            title: content.detail.name,
            posterPath: content.detail.posterPath,
            images: content.detail.images,
            selectedImageID: $selectedBackdropID,
            imageLoader: imageLoader,
            transitionNamespace: heroTransition,
            onOpenPoster: { viewModel.openPoster() },
            onOpenImage: { viewModel.openImages(initialID: $0) },
            streamingProviders: content.detail.streamingProviders,
            aspectRatio: layout.heroAspectRatio,
            part: part
        ) {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    if let nextUp = viewModel.nextUpSubtitle {
                        TVNextUpLabel(subtitle: nextUp)
                    }
                    if !content.heroMetadataLine.isEmpty {
                        Text(content.heroMetadataLine)
                            .font(DesignTypography.metadata)
                            .foregroundStyle(DesignTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(content.heroMetadataAccessibilityLabel)
                    }
                }
                if !content.detail.trailers.isEmpty {
                    MediaMetadataPills(
                        trailers: content.detail.trailers,
                        loadingTrailerID: loadingTrailerID,
                        playTrailer: { presentTrailer($0, loadingID: $loadingTrailerID, selection: $playingTrailer) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func carousels(_ content: TVSeriesContent) -> some View {
        if !content.seasons.isEmpty {
            seasonsCarousel(content)
                .id(TourAnchor.seasons.scrollID)
                .tourAnchor(.seasons)
        }
        if !content.recommendations.isEmpty {
            recommendationsCarousel(content)
        }
        if !content.detail.cast.isEmpty {
            TVCreditCarousel(
                title: "Cast",
                people: content.detail.cast,
                imageLoader: imageLoader
            ) { person in
                router?.push(.person(id: person.id))
            }
        }
        if !content.detail.directorsAndWriters.isEmpty {
            TVCreditCarousel(
                title: "Directors & Writers",
                people: content.detail.directorsAndWriters,
                imageLoader: imageLoader
            ) { person in
                router?.push(.person(id: person.id))
            }
        }
    }

    @ViewBuilder
    private func reviews(_ content: TVSeriesContent, scrollTo: @escaping (String) -> Void, columns: Int) -> some View {
        if let reviews = content.reviews {
            ReviewPageList(
                items: reviews.items,
                hasMore: reviews.hasMore,
                totalCount: reviews.totalCount,
                isLoadingPage: reviews.isLoadingPage,
                pageError: reviews.pageError,
                loadMore: { await viewModel.loadMoreReviews() },
                scrollTo: scrollTo,
                columns: columns
            )
        }
    }

    private func seasonsCarousel(_ content: TVSeriesContent) -> some View {
        DetailCarousel(title: "Seasons") {
            ForEach(content.seasons) { season in
                Button {
                    router?.push(
                        .tvSeason(
                            seriesID: content.detail.id,
                            seriesName: content.detail.name,
                            seasonNumber: season.seasonNumber,
                            seriesSnapshot: SeriesListSnapshot(detail: content.detail),
                            scrollToEpisodeNumber: nil
                        )
                    )
                } label: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        RemoteImageView(
                            path: season.posterPath,
                            kind: .poster,
                            width: 140,
                            aspectRatio: 2 / 3,
                            imageLoader: imageLoader,
                            placeholderSystemImage: "tv"
                        )
                        .carouselCard(width: 140, aspectRatio: 2 / 3)
                        .overlay(alignment: .topTrailing) {
                            CarouselRatingBadge(
                                formattedScore: viewModel.seasonScores[season.seasonNumber],
                                isWatched: viewModel.watchedSeasonNumbers.contains(season.seasonNumber)
                            )
                            .padding(DesignSpacing.xs)
                        }
                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            Text(season.name)
                                .font(DesignTypography.section.weight(.semibold))
                                .foregroundStyle(DesignTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(season.formattedAirDate)
                                .font(DesignTypography.chip)
                                .foregroundStyle(DesignTheme.textSecondary)
                            Text(season.episodeCountText)
                                .font(DesignTypography.chip)
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                        .frame(width: 140, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(seasonAccessibilityLabel(season))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func seasonAccessibilityLabel(_ season: TVSeriesContent.SeasonRow) -> String {
        var parts = [season.name, season.formattedAirDate, season.episodeCountText]
        if let score = viewModel.seasonScores[season.seasonNumber] {
            parts.append("Your rating \(score)")
        } else if viewModel.watchedSeasonNumbers.contains(season.seasonNumber) {
            parts.append("Watched")
        }
        return parts.joined(separator: ", ")
    }

    private func recommendationsCarousel(_ content: TVSeriesContent) -> some View {
        DetailCarousel(title: "Recommendations") {
            ForEach(content.recommendations) { show in
                Button {
                    router?.push(.tvSeries(id: show.id))
                } label: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        MoviePosterView(
                            posterPath: show.posterPath,
                            imageLoader: imageLoader,
                            width: 140
                        )
                        .overlay(alignment: .topTrailing) {
                            CarouselRatingBadge(
                                formattedScore: viewModel.recommendationScores[show.id],
                                isWatched: listsIndex.isOnWatched(
                                    ListEntry.itemKey(id: show.id, kind: .tv)
                                )
                            )
                            .padding(DesignSpacing.xs)
                        }
                        Text(show.name)
                            .font(DesignTypography.metadata.weight(.semibold))
                            .foregroundStyle(DesignTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 140, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(recommendationAccessibilityLabel(show))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func recommendationAccessibilityLabel(_ show: TVSeriesContent.RecommendationRow) -> String {
        var parts = [show.name]
        if let score = viewModel.recommendationScores[show.id] {
            parts.append("Your rating \(score)")
        } else if listsIndex.isOnWatched(ListEntry.itemKey(id: show.id, kind: .tv)) {
            parts.append("Watched")
        }
        return parts.joined(separator: ", ")
    }
}

/// Where each section of a series page goes.
enum TVSeriesLayout {
    enum Section: DetailPageSection {
        case hero(DetailHeroPart)
        case ratingAndStoryline
        case awards
        /// Seasons, recommendations, cast, and crew.
        case carousels
        case reviews
        case attribution

        var carriesOwnInset: Bool {
            switch self {
                case .hero, .carousels, .reviews:
                    true
                case .ratingAndStoryline, .awards, .attribution:
                    false
            }
        }
    }

    /// The sections in `shown`, placed for `layout`.
    ///
    /// - Phone and wide page: rating and storyline, with awards beside them on a wide
    ///   page; carousels and reviews run full width below.
    /// - Across a fold: the leading pane has the title, rating, storyline, and reviews;
    ///   the trailing pane has awards and the carousels.
    static func plan(for layout: DetailPageLayout, showing shown: Set<Section>) -> DetailPagePlan<Section> {
        let plan = switch layout {
            case .stacked, .columns:
                DetailPagePlan<Section>(
                    top: [.hero(.all)],
                    main: [.ratingAndStoryline],
                    side: [.awards],
                    below: [.carousels, .reviews, .attribution]
                )
            case .panes:
                DetailPagePlan<Section>(
                    top: [.hero(.backdrop)],
                    main: [.hero(.identity), .ratingAndStoryline, .reviews],
                    side: [.awards, .carousels],
                    below: [.attribution]
                )
        }
        return plan.keeping(shown.contains)
    }
}
