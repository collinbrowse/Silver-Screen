//
//  TVEpisodeView.swift
//  TheSilverScreen
//

import SwiftUI

struct TVEpisodeView: View {
    @Bindable var viewModel: TVEpisodeViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let seriesID: Int
    let seriesName: String
    let seasonNumber: Int
    var router: NavigationRouter?
    @State private var playingTrailer: MediaTrailer?
    @State private var loadingTrailerID: String?

    @Namespace private var heroTransition
    @State private var selectedBackdropID: String?

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
                        title: "Episode Unavailable",
                        message: "This episode could not be shown.",
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
            ToolbarItem(placement: .topBarTrailing) {
                ListMembershipButton(
                    draft: ListItemDraft(
                        id: seriesID,
                        kind: .tv,
                        title: seriesName,
                        imagePath: nil,
                        releaseDate: nil,
                        genreNames: [],
                        voteAverage: 0,
                        popularity: 0
                    ),
                    lists: lists,
                    index: listsIndex
                ) {
                    viewModel.noteListSaveFailed()
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
            return content.title
        }
        return ""
    }

    private func loaded(_ content: TVEpisodeContent) -> some View {
        let images = content.heroImages
        let bleedsToTop = !images.isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                episodeHero(content, images: images)
                episodeFacts(content)
                if !viewModel.awardRows.isEmpty {
                    AwardRowsSection(rows: viewModel.awardRows)
                        .padding(.horizontal, DesignSpacing.lg)
                }
                if !content.otherEpisodes.isEmpty {
                    otherEpisodes(content.otherEpisodes)
                }
                if !content.cast.isEmpty {
                    TVCreditCarousel(title: "Cast", people: content.cast, imageLoader: imageLoader) { person in
                        router?.push(.person(id: person.id))
                    }
                }
                if !content.guestStars.isEmpty {
                    TVCreditCarousel(
                        title: "Guest Stars",
                        people: content.guestStars,
                        imageLoader: imageLoader
                    ) { person in
                        router?.push(.person(id: person.id))
                    }
                }
                if !content.directorsAndWriters.isEmpty {
                    TVCreditCarousel(
                        title: "Directors & Writers",
                        people: content.directorsAndWriters,
                        imageLoader: imageLoader
                    ) { person in
                        router?.push(.person(id: person.id))
                    }
                }
            }
            .padding(.bottom, DesignSpacing.lg)
            .coordinateSpace(.named("detailScroll"))
        }
        .heroStatusBarBleed(enabled: bleedsToTop)
        .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
    }

    private func episodeHero(_ content: TVEpisodeContent, images: [MovieImage]) -> some View {
        DetailHero(
            title: content.title,
            eyebrow: seriesName,
            posterPath: nil,
            images: images,
            selectedImageID: $selectedBackdropID,
            imageLoader: imageLoader,
            transitionNamespace: heroTransition,
            onOpenPoster: {},
            onOpenImage: { viewModel.openImages(initialID: $0) }
        ) {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(content.episodeNumberText)
                    .font(DesignTypography.metadata.weight(.semibold))
                Text(content.formattedAirDate)
                if !content.trailers.isEmpty {
                    MediaMetadataPills(
                        trailers: content.trailers,
                        loadingTrailerID: loadingTrailerID,
                        playTrailer: { presentTrailer($0, loadingID: $loadingTrailerID, selection: $playingTrailer) }
                    )
                }
            }
            .font(DesignTypography.metadata)
            .foregroundStyle(DesignTheme.textSecondary)
        }
    }

    private func episodeFacts(_ content: TVEpisodeContent) -> some View {
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
                overview: content.overview,
                note: content.userNote,
                notedOn: content.formattedNotedOn,
                onSave: { await viewModel.saveUserNote($0) },
                onDelete: { await viewModel.deleteUserNote() }
            )
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    private func otherEpisodes(_ episodes: [TVEpisodeSummary]) -> some View {
        DetailCarousel(title: "More Episodes") {
            ForEach(episodes) { episode in
                Button {
                    router?.push(
                        .tvEpisode(
                            seriesID: seriesID,
                            seriesName: seriesName,
                            seasonNumber: seasonNumber,
                            episodeNumber: episode.episodeNumber
                        )
                    )
                } label: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        RemoteImageView(
                            path: episode.stillPath,
                            kind: .backdrop,
                            width: 200,
                            aspectRatio: 16 / 9,
                            imageLoader: imageLoader,
                            placeholderSystemImage: "tv"
                        )
                        .carouselCard(width: 200, aspectRatio: 16 / 9)
                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            Text(episode.title)
                                .font(DesignTypography.metadata.weight(.semibold))
                                .foregroundStyle(DesignTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Episode \(episode.episodeNumber)")
                                .font(DesignTypography.chip)
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                        .frame(width: 200, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(episode.title), Episode \(episode.episodeNumber)")
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}
