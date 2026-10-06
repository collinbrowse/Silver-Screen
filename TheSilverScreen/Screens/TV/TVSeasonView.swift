//
//  TVSeasonView.swift
//  TheSilverScreen
//

import SwiftUI

struct TVSeasonView: View {
    @Bindable var viewModel: TVSeasonViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var router: NavigationRouter?
    @State private var playingTrailer: MediaTrailer?
    @State private var loadingTrailerID: String?
    let seriesID: Int
    let seasonNumber: Int

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
                        title: "Season Unavailable",
                        message: "This season could not be shown.",
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
                        draft: seriesDraft(
                            named: content.seriesName,
                            seasonPosterPath: content.posterPath
                        ),
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
            return content.displayName
        }
        return ""
    }

    private func loaded(_ content: TVSeasonContent) -> some View {
        let bleedsToTop = !content.images.isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                seasonHero(content)
                seasonFacts(content)
                if !viewModel.awardRows.isEmpty {
                    AwardRowsSection(rows: viewModel.awardRows)
                        .padding(.horizontal, DesignSpacing.lg)
                }
                if !content.cast.isEmpty {
                    TVCreditCarousel(title: "Cast", people: content.cast, imageLoader: imageLoader) { person in
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
                if !content.episodes.isEmpty {
                    episodes(content.episodes, seriesName: content.seriesName)
                }
                if !content.streamingProviders.isEmpty {
                    JustWatchAttributionFooter()
                        .padding(.horizontal, DesignSpacing.lg)
                }
            }
            .padding(.bottom, DesignSpacing.lg)
            .coordinateSpace(.named("detailScroll"))
        }
        .heroStatusBarBleed(enabled: bleedsToTop)
        .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
    }

    private func seasonHero(_ content: TVSeasonContent) -> some View {
        DetailHero(
            title: content.displayName,
            eyebrow: content.seriesName,
            posterPath: content.posterPath,
            images: content.images,
            selectedImageID: $selectedBackdropID,
            imageLoader: imageLoader,
            transitionNamespace: heroTransition,
            onOpenPoster: { viewModel.openPoster() },
            onOpenImage: { viewModel.openImages(initialID: $0) },
            streamingProviders: content.streamingProviders
        ) {
            Text(content.formattedAirDate)
                .font(DesignTypography.metadata)
                .foregroundStyle(DesignTheme.textSecondary)
            if !content.trailers.isEmpty {
                MediaMetadataPills(
                    trailers: content.trailers,
                    loadingTrailerID: loadingTrailerID,
                    playTrailer: { presentTrailer($0, loadingID: $loadingTrailerID, selection: $playingTrailer) }
                )
            }
        }
    }

    private func seasonFacts(_ content: TVSeasonContent) -> some View {
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

    /// Season and episode screens save the series, using series fields plus season art when present.
    private func seriesDraft(named name: String, seasonPosterPath: String?) -> ListItemDraft {
        viewModel.seriesSnapshot.listItem(id: seriesID, title: name, imagePath: seasonPosterPath)
    }

    private func episodes(_ episodes: [TVEpisodeSummary], seriesName: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("Episodes")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, DesignSpacing.lg)

            ForEach(episodes) { episode in
                Button {
                    router?.push(
                        .tvEpisode(
                            seriesID: seriesID,
                            seriesName: seriesName,
                            seasonNumber: seasonNumber,
                            episodeNumber: episode.episodeNumber,
                            seriesSnapshot: viewModel.seriesSnapshot
                        )
                    )
                } label: {
                    episodeRow(episode)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignSpacing.lg)
            }
        }
    }

    private func episodeRow(_ episode: TVEpisodeSummary) -> some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            RemoteImageView(
                path: episode.stillPath,
                kind: .backdrop,
                width: 120,
                aspectRatio: 16 / 9,
                imageLoader: imageLoader,
                placeholderSystemImage: "tv"
            )
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(episode.title)
                    .font(DesignTypography.metadata.weight(.semibold))
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Episode \(episode.episodeNumber)")
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
                if !episode.overview.isEmpty {
                    Text(episode.overview)
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(DisplayDate.day(episode.airDate))
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
                Text(episode.directorLine)
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(episodeLabel(episode))
        .accessibilityAddTraits(.isButton)
    }

    private func episodeLabel(_ episode: TVEpisodeSummary) -> String {
        let director = episode.directorLine
        return "\(episode.title), Episode \(episode.episodeNumber), \(DisplayDate.day(episode.airDate)), \(director)"
    }
}
