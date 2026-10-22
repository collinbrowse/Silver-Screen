//
//  TVSeasonView.swift
//  SilverScreen
//

import SwiftUI

/// Confirm payload for marking or clearing a season via the toolbar eye.
private enum SeasonWatchConfirm: Equatable {
    case markSeason(episodeCount: Int)
    case clearSeason(episodeCount: Int)

    var episodeCount: Int {
        switch self {
            case .markSeason(let count), .clearSeason(let count):
                return count
        }
    }

    var isClear: Bool {
        if case .clearSeason = self { return true }
        return false
    }
}

struct TVSeasonView: View {
    @Bindable var viewModel: TVSeasonViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let tvWatch: TVWatchRepository
    var router: NavigationRouter?

    @Environment(ListChangeNotice.self) private var notice
    @State private var playingTrailer: MediaTrailer?
    @State private var loadingTrailerID: String?
    let seriesID: Int
    let seasonNumber: Int
    /// When set (In Progress continue), scroll so this episode sits at the top after load.
    /// Library passes one episode above last watched when possible.
    var scrollToEpisodeNumber: Int? = nil

    @Namespace private var heroTransition
    @State private var selectedBackdropID: String?
    @State private var didScrollToFocusedEpisode = false
    /// Status-bar band; used to lift the continue-scroll anchor below the nav title.
    @State private var statusBarHeight: CGFloat = 0
    /// Pending mark-season confirm before bulk-completing unmarked episodes.
    @State private var pendingConfirm: SeasonWatchConfirm?
    /// Separate from `pendingConfirm` so dismissing the alert cannot clear the
    /// payload before the confirm button’s action reads it (SwiftUI race).
    @State private var isSeasonConfirmPresented = false

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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleSeasonWatched() }
                    } label: {
                        Image(systemName: viewModel.isSeasonFullyWatched ? "eye.fill" : "eye")
                            .foregroundStyle(
                                viewModel.isSeasonFullyWatched
                                    ? DesignTheme.accent
                                    : DesignTheme.textPrimary
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(
                        viewModel.isSeasonFullyWatched
                            ? "Mark season not watched"
                            : "Mark season watched"
                    )
                    .accessibilityValue(
                        viewModel.isSeasonFullyWatched ? "Watched" : "Not watched"
                    )

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
        .alert(
            pendingConfirm?.isClear == true
                ? TVWatchConfirm.clearSeasonTitle
                : TVWatchConfirm.seasonTitle,
            isPresented: $isSeasonConfirmPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingConfirm = nil
            }
            if pendingConfirm?.isClear == true {
                Button(TVWatchConfirm.clearButtonTitle, role: .destructive) {
                    confirmPendingSeasonAction()
                }
            } else {
                Button(TVWatchConfirm.confirmButtonTitle) {
                    confirmPendingSeasonAction()
                }
            }
        } message: {
            if let pending = pendingConfirm {
                Text(
                    pending.isClear
                        ? TVWatchConfirm.clearMessage(episodeCount: pending.episodeCount)
                        : TVWatchConfirm.message(episodeCount: pending.episodeCount)
                )
            }
        }
        .onChange(of: notice.ratingKey) { _, key in
            // Toast rating just saved (key cleared) — refresh TMDB card + episode badges.
            if key == nil {
                Task {
                    await viewModel.reloadPersonalFromStore()
                    await viewModel.reloadEpisodeScores()
                }
            }
        }
        .onChange(of: notice.watchRevision) { _, _ in
            Task { await viewModel.reloadWatchChrome() }
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
            return content.displayName
        }
        return ""
    }

    private func loaded(_ content: TVSeasonContent) -> some View {
        let bleedsToTop = !content.images.isEmpty
        return DetailPageReader { page in
            ScrollViewReader { proxy in
                ScrollView {
                    DetailPageSections(
                        page: page,
                        plan: TVSeasonLayout.plan(for: page.layout, showing: shownSections(content))
                    ) { section, slot in
                        sectionView(section, in: slot, layout: page.layout, content: content) { id in
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .padding(.bottom, DesignSpacing.lg)
                    .readableColumn(maxWidth: page.layout.columnCap)
                    .coordinateSpace(.named("detailScroll"))
                }
                .heroStatusBarBleed(enabled: bleedsToTop)
                .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
                .background {
                    WindowTopInsetReader { top in
                        if top != statusBarHeight {
                            statusBarHeight = top
                        }
                    }
                    .frame(width: 0, height: 0)
                }
                .task(id: content.episodes.map(\.episodeNumber)) {
                    await scrollToFocusedEpisodeIfNeeded(proxy: proxy, episodes: content.episodes)
                }
                .onChange(of: statusBarHeight) { _, height in
                    guard height > 0, !didScrollToFocusedEpisode else { return }
                    Task {
                        await scrollToFocusedEpisodeIfNeeded(proxy: proxy, episodes: content.episodes)
                    }
                }
            }
        }
    }

    private func shownSections(_ content: TVSeasonContent) -> Set<TVSeasonLayout.Section> {
        var shown: Set<TVSeasonLayout.Section> = [
            .hero(.all), .hero(.backdrop), .hero(.identity), .ratingAndOverview,
        ]
        if !viewModel.awardRows.isEmpty { shown.insert(.awards) }
        if !content.cast.isEmpty || !content.directorsAndWriters.isEmpty { shown.insert(.credits) }
        if !content.episodes.isEmpty { shown.insert(.episodes) }
        if !content.streamingProviders.isEmpty { shown.insert(.attribution) }
        return shown
    }

    @ViewBuilder
    private func sectionView(
        _ section: TVSeasonLayout.Section,
        in slot: DetailSlot,
        layout: DetailPageLayout,
        content: TVSeasonContent,
        scrollTo: @escaping (String) -> Void
    ) -> some View {
        switch section {
            case .hero(let part):
                seasonHero(content, layout: layout, part: part)
            case .ratingAndOverview:
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    ratingAndOverview(content, scrollTo: scrollTo)
                }
            case .awards:
                AwardRowsSection(rows: viewModel.awardRows)
            case .credits:
                credits(content)
            case .episodes:
                episodes(content.episodes, seriesName: content.seriesName, columns: layout.gridColumns(in: slot))
            case .attribution:
                JustWatchAttributionFooter()
        }
    }

    /// Distance to lift the scroll target so the episode sits below the inline title bar.
    /// Hero bleed zeros top content margins, so `scrollTo(..., .top)` would otherwise hide
    /// the row under the nav chrome.
    private var focusedEpisodeScrollLift: CGFloat {
        let status = statusBarHeight > 0 ? statusBarHeight : 59
        return status + 44 + DesignSpacing.sm
    }

    /// Pins the focused episode (continue anchor from In Progress) just below the title bar once.
    /// Latches only after a measured status-bar inset so a later probe update can re-try.
    private func scrollToFocusedEpisodeIfNeeded(
        proxy: ScrollViewProxy,
        episodes: [TVEpisodeSummary]
    ) async {
        guard let target = scrollToEpisodeNumber,
              !didScrollToFocusedEpisode,
              episodes.contains(where: { $0.episodeNumber == target }) else {
            return
        }
        // Let rows lay out and the status-bar probe report before scrolling.
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        for _ in 0..<8 where statusBarHeight == 0 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(Self.episodeScrollID(target), anchor: .top)
        }
        // Only latch once we had a measured inset (or timed out waiting). That lets
        // onChange(statusBarHeight) re-try when the probe reports after the first pass.
        if statusBarHeight > 0 {
            didScrollToFocusedEpisode = true
        }
    }

    private static func episodeScrollID(_ episodeNumber: Int) -> String {
        "season-episode-\(episodeNumber)"
    }

    private func seasonHero(_ content: TVSeasonContent, layout: DetailPageLayout, part: DetailHeroPart) -> some View {
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
            streamingProviders: content.streamingProviders,
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
                if !content.trailers.isEmpty {
                    MediaMetadataPills(
                        trailers: content.trailers,
                        loadingTrailerID: loadingTrailerID,
                        playTrailer: { presentTrailer($0, loadingID: $loadingTrailerID, selection: $playingTrailer) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func ratingAndOverview(_ content: TVSeasonContent, scrollTo: @escaping (String) -> Void) -> some View {
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

    @ViewBuilder
    private func credits(_ content: TVSeasonContent) -> some View {
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
    }

    /// Season and episode screens save the series, using series fields plus season art when present.
    private func seriesDraft(named name: String, seasonPosterPath: String?) -> ListItemDraft {
        viewModel.seriesSnapshot.listItem(id: seriesID, title: name, imagePath: seasonPosterPath)
    }

    private func toggleSeasonWatched() async {
        if viewModel.isSeasonFullyWatched {
            await requestClearSeasonWatched()
        } else {
            await requestMarkSeasonWatched()
        }
    }

    private func requestMarkSeasonWatched() async {
        let unmarked = await viewModel.unmarkedEpisodeCountForSeason()
        guard unmarked > 0 else { return }
        pendingConfirm = .markSeason(episodeCount: unmarked)
        isSeasonConfirmPresented = true
    }

    private func requestClearSeasonWatched() async {
        let count = viewModel.completedEpisodeNumbers.count
        if count > 1 {
            pendingConfirm = .clearSeason(episodeCount: count)
            isSeasonConfirmPresented = true
        } else {
            await performUnmarkSeasonWatched()
        }
    }

    /// Captures `pendingConfirm` synchronously so alert dismissal cannot nil it first.
    private func confirmPendingSeasonAction() {
        guard let pending = pendingConfirm else { return }
        pendingConfirm = nil
        isSeasonConfirmPresented = false
        Task {
            switch pending {
                case .markSeason:
                    await performMarkSeasonWatched()
                case .clearSeason:
                    await performUnmarkSeasonWatched()
            }
        }
    }

    private func performMarkSeasonWatched() async {
        guard let outcome = await viewModel.markSeasonWatched(),
              outcome.episodesNewlyMarked > 0
                || outcome.membershipChange?.confirmation != nil
        else { return }
        notice.presentWatch(
            outcome,
            ratingKey: ratingKey(for: outcome),
            fallbackMessage: "Season watched",
            using: lists,
            tvWatch: tvWatch
        )
    }

    private func performUnmarkSeasonWatched() async {
        guard let outcome = await viewModel.unmarkSeasonWatched() else { return }
        if let change = outcome.membershipChange, change.confirmation != nil {
            notice.show(
                change,
                using: lists,
                tvWatch: tvWatch,
                watchUndo: outcome.watchUndo
            )
        }
    }

    /// Prefer series rating when the season mark finished the show (Watched move).
    private func ratingKey(for outcome: TVWatchOutcome) -> AnnotationKey {
        if outcome.state.catalogSnapshot != nil {
            return .series(seriesID)
        }
        return .season(seriesID: seriesID, seasonNumber: seasonNumber)
    }

    private func toggleEpisodeWatch(_ episode: TVEpisodeSummary) async {
        let wasCompleted = viewModel.completedEpisodeNumbers.contains(episode.episodeNumber)
        let ratingKey = AnnotationKey.episode(
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            episodeNumber: episode.episodeNumber
        )
        guard let outcome = await viewModel.toggleEpisodeWatched(episode) else {
            await viewModel.reloadEpisodeScores()
            return
        }
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
        await viewModel.reloadEpisodeScores()
    }

    /// One episode per row on a phone, `columns` per row on a wide page. A plain
    /// `Grid` rather than a lazy one: Continue scrolls to an episode by id, so every
    /// row has to exist.
    private func episodes(_ episodes: [TVEpisodeSummary], seriesName: String, columns: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("Episodes")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Grid(
                alignment: .topLeading,
                horizontalSpacing: DesignSpacing.lg,
                verticalSpacing: DesignSpacing.md
            ) {
                ForEach(CatalogGrid.rows(episodes, columns: columns, id: \.id)) { row in
                    GridRow {
                        ForEach(row.items) { episode in
                            episodeCell(episode, seriesName: seriesName)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    private func episodeCell(_ episode: TVEpisodeSummary, seriesName: String) -> some View {
        let isContinueFocus = scrollToEpisodeNumber == episode.episodeNumber
        return VStack(spacing: 0) {
            // Laid-out anchor above the row (collapsed visually via negative
            // padding) so scrollTo(.top) clears the nav title bar.
            if isContinueFocus {
                Color.clear
                    .frame(height: focusedEpisodeScrollLift)
                    .id(Self.episodeScrollID(episode.episodeNumber))
                    .padding(.bottom, -focusedEpisodeScrollLift)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .top, spacing: DesignSpacing.sm) {
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

                EpisodeWatchButton(
                    isCompleted: viewModel.completedEpisodeNumbers.contains(episode.episodeNumber),
                    accessibilityTitle: episode.title
                ) {
                    Task { await toggleEpisodeWatch(episode) }
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                if let score = viewModel.episodeScores[episode.episodeNumber] {
                    Text(score)
                        .font(DesignTypography.chip.weight(.semibold))
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityLabel("Your rating, \(score)")
                }
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
        var parts = [
            episode.title,
            "Episode \(episode.episodeNumber)",
            DisplayDate.day(episode.airDate),
            episode.directorLine,
        ]
        if let score = viewModel.episodeScores[episode.episodeNumber] {
            parts.append("Your rating \(score)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Where each section of a season page goes.
enum TVSeasonLayout {
    enum Section: DetailPageSection {
        case hero(DetailHeroPart)
        case ratingAndOverview
        case awards
        /// Cast, and directors and writers.
        case credits
        case episodes
        case attribution

        var carriesOwnInset: Bool {
            switch self {
                case .hero, .credits, .episodes:
                    true
                case .ratingAndOverview, .awards, .attribution:
                    false
            }
        }
    }

    /// The sections in `shown`, placed for `layout`.
    ///
    /// - Phone and wide page: rating and overview, with awards beside them on a wide
    ///   page; the credits and episodes run full width below, episodes two to a row on
    ///   a wide page.
    /// - Across a fold: the leading pane has the title and the episodes, one per row;
    ///   the trailing pane has the rating and overview, awards, and the credits.
    static func plan(for layout: DetailPageLayout, showing shown: Set<Section>) -> DetailPagePlan<Section> {
        let plan = switch layout {
            case .stacked, .columns:
                DetailPagePlan<Section>(
                    top: [.hero(.all)],
                    main: [.ratingAndOverview],
                    side: [.awards],
                    below: [.credits, .episodes, .attribution]
                )
            case .panes:
                DetailPagePlan<Section>(
                    top: [.hero(.backdrop)],
                    main: [.hero(.identity), .episodes],
                    side: [.ratingAndOverview, .awards, .credits],
                    below: [.attribution]
                )
        }
        return plan.keeping(shown.contains)
    }
}
