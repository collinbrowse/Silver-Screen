//
//  TVEpisodeView.swift
//  SilverScreen
//

import SwiftUI

struct TVEpisodeView: View {
    @Bindable var viewModel: TVEpisodeViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let tvWatch: TVWatchRepository
    let seriesID: Int
    let seriesName: String
    let seasonNumber: Int
    let episodeNumber: Int
    var router: NavigationRouter?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ListChangeNotice.self) private var notice
    @State private var playingTrailer: MediaTrailer?
    @State private var loadingTrailerID: String?
    /// True while the iPhone Duo's fold crosses the page; see `episodeFacts`.
    @State private var isFolded = false

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
            if case .loaded = viewModel.state {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EpisodeWatchButton(
                        isCompleted: viewModel.isEpisodeCompleted,
                        accessibilityTitle: navigationTitle.isEmpty ? "episode" : navigationTitle,
                        idleColor: DesignTheme.textPrimary
                    ) {
                        Task {
                            let wasCompleted = viewModel.isEpisodeCompleted
                            let ratingKey = AnnotationKey.episode(
                                seriesID: seriesID,
                                seasonNumber: seasonNumber,
                                episodeNumber: episodeNumber
                            )
                            guard let outcome = await viewModel.toggleEpisodeWatched(
                                seriesTitle: seriesName
                            ) else { return }
                            if wasCompleted {
                                if let change = outcome.membershipChange, change.confirmation != nil {
                                    notice.show(
                                        change,
                                        using: lists,
                                        tvWatch: tvWatch,
                                        watchUndo: outcome.watchUndo
                                    )
                                }
                            } else {
                                notice.presentWatch(
                                    outcome,
                                    ratingKey: ratingKey,
                                    fallbackMessage: "Episode watched",
                                    using: lists,
                                    tvWatch: tvWatch
                                )
                            }
                        }
                    }

                    ListMembershipButton(
                        draft: viewModel.seriesSnapshot.listItem(id: seriesID, title: seriesName),
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
        .onChange(of: notice.ratingKey) { _, key in
            if key == nil {
                Task { await viewModel.reloadPersonalFromStore() }
            }
        }
        .onChange(of: notice.watchRevision) { _, _ in
            Task { await viewModel.reloadEpisodeCompleted() }
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
            return content.title
        }
        return ""
    }

    private func loaded(_ content: TVEpisodeContent) -> some View {
        let images = content.heroImages
        let bleedsToTop = !images.isEmpty
        // Read here, in the view's own body, so a fold change re-renders the page; a
        // state read only inside the width reader's closure would not.
        let pageIsFolded = isFolded
        return ContentWidthReader { width in
            let twoColumns = DetailLayoutMetrics.usesTwoColumns(
                forWidth: width,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
            let contentWidth = DetailLayoutMetrics.contentWidth(forWidth: width, twoColumns: twoColumns)
            let sectionsInPanes = twoColumns && pageIsFolded
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                        episodeHero(
                            content,
                            images: images,
                            twoColumns: twoColumns,
                            part: sectionsInPanes ? .backdrop : .all
                        )
                        episodeFacts(
                            content,
                            scrollTo: { id in
                                proxy.scrollTo(id, anchor: .top)
                            },
                            twoColumns: twoColumns,
                            contentWidth: contentWidth,
                            sectionsInPanes: sectionsInPanes
                        )
                        if !sectionsInPanes {
                            if !content.otherEpisodes.isEmpty {
                                otherEpisodes(content.otherEpisodes)
                            }
                            credits(content)
                        }
                        if !content.streamingProviders.isEmpty {
                            JustWatchAttributionFooter()
                                .padding(.horizontal, DesignSpacing.lg)
                        }
                    }
                    .padding(.bottom, DesignSpacing.lg)
                    .readableColumn(maxWidth: DetailLayoutMetrics.columnCap(twoColumns: twoColumns))
                    .coordinateSpace(.named("detailScroll"))
                }
                .onFoldSplitChange { isFolded = $0 != nil }
            }
            .heroStatusBarBleed(enabled: bleedsToTop)
            .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
        }
    }

    private func episodeHero(
        _ content: TVEpisodeContent,
        images: [MovieImage],
        twoColumns: Bool,
        part: DetailHeroPart
    ) -> some View {
        DetailHero(
            title: content.title,
            eyebrow: seriesName,
            posterPath: nil,
            images: images,
            selectedImageID: $selectedBackdropID,
            imageLoader: imageLoader,
            transitionNamespace: heroTransition,
            onOpenPoster: {},
            onOpenImage: { viewModel.openImages(initialID: $0) },
            streamingProviders: content.streamingProviders,
            aspectRatio: DetailLayoutMetrics.heroAspectRatio(twoColumns: twoColumns),
            part: part
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

    /// Rating and overview, with awards beside them on a wide page and below them on
    /// a phone. With `sectionsInPanes` (the iPhone Duo's hinge is bent) the leading pane
    /// holds the title, rating, and overview, and the trailing pane holds More Episodes,
    /// awards, and the credits, starting beside the title.
    private func episodeFacts(
        _ content: TVEpisodeContent,
        scrollTo: @escaping (String) -> Void,
        twoColumns: Bool,
        contentWidth: CGFloat,
        sectionsInPanes: Bool
    ) -> some View {
        DetailColumns(
            twoColumns: twoColumns,
            contentWidth: contentWidth,
            showsSecondary: sectionsInPanes || !viewModel.awardRows.isEmpty,
            itemSpacing: DesignSpacing.md,
            secondaryTopInset: sectionsInPanes
                ? DetailHeroPart.titleTopOffset(posterPath: nil, hasImages: !content.heroImages.isEmpty)
                : 0
        ) {
            if sectionsInPanes {
                episodeHero(content, images: content.heroImages, twoColumns: true, part: .identity)
                    .inPane()
                    .padding(.bottom, DesignSpacing.xl - DesignSpacing.md)
            }
            TMDBRatingCard(
                formattedRating: content.formattedRating,
                accessibilityLabel: content.ratingAccessibilityLabel,
                formattedUserScore: content.formattedUserScore,
                userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
                onEdit: { viewModel.openAnnotationEditor() }
            )
            MediaDescriptionSection(
                overview: content.overview,
                note: content.userNote,
                notedOn: content.formattedNotedOn,
                onEdit: { viewModel.openAnnotationEditor() },
                scrollTo: scrollTo
            )
        } secondary: {
            if sectionsInPanes, !content.otherEpisodes.isEmpty {
                otherEpisodes(content.otherEpisodes)
                    .inPane()
                    .padding(.bottom, DesignSpacing.xl - DesignSpacing.md)
            }
            if !viewModel.awardRows.isEmpty {
                AwardRowsSection(rows: viewModel.awardRows)
            }
            if sectionsInPanes {
                credits(content)
                    .inPane()
            }
        }
        .detailColumnsInset(hingePanes: sectionsInPanes)
    }

    @ViewBuilder
    private func credits(_ content: TVEpisodeContent) -> some View {
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

    private func otherEpisodes(_ episodes: [TVEpisodeSummary]) -> some View {
        DetailCarousel(title: "More Episodes") {
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
