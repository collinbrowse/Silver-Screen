//
//  TVSeriesView.swift
//  TheSilverScreen
//

import SwiftUI

struct TVSeriesView: View {
    @Bindable var viewModel: TVSeriesViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var router: NavigationRouter?

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

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                ToolbarItem(placement: .topBarTrailing) {
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
        .trailerPlayer($playingTrailer, loadingID: $loadingTrailerID)
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
        }
    }

    private func seriesScroll(_ content: TVSeriesContent, scrollTo: @escaping (String) -> Void) -> some View {
        let bleedsToTop = !content.detail.images.isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                seriesHero(content)
                seriesFacts(content)
                if !viewModel.awardRows.isEmpty {
                    AwardRowsSection(rows: viewModel.awardRows)
                        .padding(.horizontal, DesignSpacing.lg)
                }
                if !content.seasons.isEmpty {
                    seasonsCarousel(content)
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
                if let reviews = content.reviews {
                    ReviewPageList(
                        items: reviews.items,
                        hasMore: reviews.hasMore,
                        totalCount: reviews.totalCount,
                        isLoadingPage: reviews.isLoadingPage,
                        pageError: reviews.pageError,
                        loadMore: { await viewModel.loadMoreReviews() },
                        scrollTo: scrollTo
                    )
                }
            }
            .padding(.bottom, DesignSpacing.lg)
            .coordinateSpace(.named("detailScroll"))
        }
        .heroStatusBarBleed(enabled: bleedsToTop)
        .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
        .refreshable {
            await viewModel.refresh()
        }
    }

    private func seriesHero(_ content: TVSeriesContent) -> some View {
        DetailHero(
            title: content.detail.name,
            posterPath: content.detail.posterPath,
            images: content.detail.images,
            selectedImageID: $selectedBackdropID,
            imageLoader: imageLoader,
            transitionNamespace: heroTransition,
            onOpenPoster: { viewModel.openPoster() },
            onOpenImage: { viewModel.openImages(initialID: $0) },
            genreNames: content.detail.genres.map(\.name)
        ) {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text("First aired \(content.formattedFirstAirDate)")
                Text(content.formattedLastAirDate)
                Text(content.creatorsText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(DesignTypography.metadata)
            .foregroundStyle(DesignTheme.textSecondary)
            if !content.detail.trailers.isEmpty {
                MediaMetadataPills(
                    trailers: content.detail.trailers,
                    loadingTrailerID: loadingTrailerID,
                    playTrailer: { presentTrailer($0, loadingID: $loadingTrailerID, selection: $playingTrailer) }
                )
            }
        }
    }

    private func seriesFacts(_ content: TVSeriesContent) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            TMDBRatingCard(
                formattedRating: content.formattedRating,
                accessibilityLabel: content.ratingAccessibilityLabel,
                formattedUserScore: content.formattedUserScore,
                userScoreAccessibilityLabel: content.userScoreAccessibilityLabel
            ) { score in
                Task { await viewModel.saveUserScore(score) }
            }
            MediaDescriptionSection(
                overview: content.detail.overview,
                note: content.userNote,
                notedOn: content.formattedNotedOn,
                onSave: { await viewModel.saveUserNote($0) },
                onDelete: { await viewModel.deleteUserNote() }
            )
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    private func seasonsCarousel(_ content: TVSeriesContent) -> some View {
        DetailCarousel(title: "Seasons") {
            ForEach(content.seasons) { season in
                Button {
                    router?.push(
                        .tvSeason(
                            seriesID: content.detail.id,
                            seriesName: content.detail.name,
                            seasonNumber: season.seasonNumber
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
                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            Text(season.name)
                                .font(DesignTypography.metadata.weight(.semibold))
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
                .accessibilityLabel("\(season.name), \(season.formattedAirDate), \(season.episodeCountText)")
                .accessibilityAddTraits(.isButton)
            }
        }
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
                        Text(show.name)
                            .font(DesignTypography.metadata.weight(.semibold))
                            .foregroundStyle(DesignTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 140, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(show.name)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}
