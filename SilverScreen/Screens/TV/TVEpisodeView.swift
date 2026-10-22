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

    @Environment(ListChangeNotice.self) private var notice
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
        let bleedsToTop = !content.heroImages.isEmpty
        return DetailPageReader { page in
            ScrollViewReader { proxy in
                ScrollView {
                    DetailPageSections(
                        page: page,
                        plan: TVEpisodeLayout.plan(for: page.layout, showing: shownSections(content))
                    ) { section, _ in
                        sectionView(section, layout: page.layout, content: content) { id in
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .padding(.bottom, DesignSpacing.lg)
                    .readableColumn(maxWidth: page.layout.columnCap)
                    .coordinateSpace(.named("detailScroll"))
                }
            }
            .heroStatusBarBleed(enabled: bleedsToTop)
            .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
        }
    }

    private func shownSections(_ content: TVEpisodeContent) -> Set<TVEpisodeLayout.Section> {
        var shown: Set<TVEpisodeLayout.Section> = [
            .hero(.all), .hero(.backdrop), .hero(.identity), .ratingAndOverview,
        ]
        if !viewModel.awardRows.isEmpty { shown.insert(.awards) }
        if !content.otherEpisodes.isEmpty { shown.insert(.otherEpisodes) }
        if !content.cast.isEmpty || !content.guestStars.isEmpty || !content.directorsAndWriters.isEmpty {
            shown.insert(.credits)
        }
        if !content.streamingProviders.isEmpty { shown.insert(.attribution) }
        return shown
    }

    @ViewBuilder
    private func sectionView(
        _ section: TVEpisodeLayout.Section,
        layout: DetailPageLayout,
        content: TVEpisodeContent,
        scrollTo: @escaping (String) -> Void
    ) -> some View {
        switch section {
            case .hero(let part):
                episodeHero(content, images: content.heroImages, layout: layout, part: part)
            case .ratingAndOverview:
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
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
                }
            case .awards:
                AwardRowsSection(rows: viewModel.awardRows)
            case .otherEpisodes:
                otherEpisodes(content.otherEpisodes)
            case .credits:
                credits(content)
            case .attribution:
                JustWatchAttributionFooter()
        }
    }

    private func episodeHero(
        _ content: TVEpisodeContent,
        images: [MovieImage],
        layout: DetailPageLayout,
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
            aspectRatio: layout.heroAspectRatio,
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

/// Where each section of an episode page goes.
enum TVEpisodeLayout {
    enum Section: DetailPageSection {
        case hero(DetailHeroPart)
        case ratingAndOverview
        case awards
        /// The season's other episodes.
        case otherEpisodes
        /// Cast, guest stars, and directors and writers.
        case credits
        case attribution

        var carriesOwnInset: Bool {
            switch self {
                case .hero, .otherEpisodes, .credits:
                    true
                case .ratingAndOverview, .awards, .attribution:
                    false
            }
        }
    }

    /// The sections in `shown`, placed for `layout`.
    ///
    /// - Phone and wide page: rating and overview, with awards beside them on a wide
    ///   page; More Episodes and the credits run full width below.
    /// - Across a fold: the leading pane has the title, rating, and overview; the
    ///   trailing pane has More Episodes, awards, and the credits.
    static func plan(for layout: DetailPageLayout, showing shown: Set<Section>) -> DetailPagePlan<Section> {
        let plan = switch layout {
            case .stacked, .columns:
                DetailPagePlan<Section>(
                    top: [.hero(.all)],
                    main: [.ratingAndOverview],
                    side: [.awards],
                    below: [.otherEpisodes, .credits, .attribution]
                )
            case .panes:
                DetailPagePlan<Section>(
                    top: [.hero(.backdrop)],
                    main: [.hero(.identity), .ratingAndOverview],
                    side: [.otherEpisodes, .awards, .credits],
                    below: [.attribution]
                )
        }
        return plan.keeping(shown.contains)
    }
}
