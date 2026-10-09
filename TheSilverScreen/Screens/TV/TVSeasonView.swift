//
//  TVSeasonView.swift
//  TheSilverScreen
//

import SwiftUI

/// Confirm payload for marking a season watched (eye or rating path).
private enum SeasonWatchConfirm: Equatable {
    case markSeason(episodeCount: Int)
    case rateAndMark(score: Double, episodeCount: Int)

    var episodeCount: Int {
        switch self {
            case .markSeason(let count), .rateAndMark(_, let count):
                return count
        }
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
    var scrollToEpisodeNumber: Int? = nil

    @Namespace private var heroTransition
    @State private var selectedBackdropID: String?
    @State private var didScrollToFocusedEpisode = false
    /// Status-bar band; used to lift the continue-scroll anchor below the nav title.
    @State private var statusBarHeight: CGFloat = 0
    /// Pending mark-season or rate-and-mark confirm (Story 5).
    @State private var pendingConfirm: SeasonWatchConfirm?

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
                    HStack(spacing: 4) {
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
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
        .alert(TVWatchConfirm.seasonTitle, isPresented: seasonConfirmPresented) {
            Button("Cancel", role: .cancel) {
                pendingConfirm = nil
            }
            Button(TVWatchConfirm.confirmButtonTitle) {
                Task { await confirmPendingSeasonAction() }
            }
        } message: {
            if let count = pendingConfirm?.episodeCount {
                Text(TVWatchConfirm.message(episodeCount: count))
            }
        }
        .onChange(of: notice.ratingKey) { _, key in
            // Toast rating just saved (key cleared) — refresh episode score badges.
            if key == nil {
                Task { await viewModel.reloadEpisodeScores() }
            }
        }
        .onChange(of: notice.watchRevision) { _, _ in
            Task { await viewModel.reloadWatchChrome() }
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
        return ScrollViewReader { proxy in
            ScrollView {
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
        }
    }

    /// Distance to lift the scroll target so the episode sits below the inline title bar.
    /// Hero bleed zeros top content margins, so `scrollTo(..., .top)` would otherwise hide
    /// the row under the nav chrome.
    private var focusedEpisodeScrollLift: CGFloat {
        let status = statusBarHeight > 0 ? statusBarHeight : 59
        return status + 44 + DesignSpacing.sm
    }

    /// Pins the focused episode (last watched from In Progress) just below the title bar once.
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
        for _ in 0..<6 where statusBarHeight == 0 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(Self.episodeScrollID(target), anchor: .top)
        }
        // Only latch after a successful scroll attempt so a cancelled task can retry.
        didScrollToFocusedEpisode = true
    }

    private static func episodeScrollID(_ episodeNumber: Int) -> String {
        "season-episode-\(episodeNumber)"
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
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                if !content.heroMetadataLine.isEmpty {
                    Text(content.heroMetadataLine)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(content.heroMetadataAccessibilityLabel)
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

    private func seasonFacts(_ content: TVSeasonContent) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            if let nextUp = viewModel.nextUpSubtitle {
                TVNextUpLabel(subtitle: nextUp)
            }
            TMDBRatingCard(
                formattedRating: content.formattedRating,
                accessibilityLabel: content.ratingAccessibilityLabel,
                formattedUserScore: content.formattedUserScore,
                userScoreAccessibilityLabel: content.userScoreAccessibilityLabel
            ) { score in
                Task { await requestSaveScore(score) }
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

    private var seasonConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingConfirm != nil },
            set: { presented in
                if !presented { pendingConfirm = nil }
            }
        )
    }

    private func toggleSeasonWatched() async {
        if viewModel.isSeasonFullyWatched {
            await performUnmarkSeasonWatched()
        } else {
            await requestMarkSeasonWatched()
        }
    }

    private func requestMarkSeasonWatched() async {
        let unmarked = await viewModel.unmarkedEpisodeCountForSeason()
        guard unmarked > 0 else { return }
        pendingConfirm = .markSeason(episodeCount: unmarked)
    }

    private func requestSaveScore(_ score: Double) async {
        let unmarked = await viewModel.unmarkedEpisodeCountForSeason()
        if unmarked > 0 {
            pendingConfirm = .rateAndMark(score: score, episodeCount: unmarked)
        } else {
            await performSaveScore(score)
        }
    }

    private func confirmPendingSeasonAction() async {
        guard let pending = pendingConfirm else { return }
        pendingConfirm = nil
        switch pending {
            case .markSeason:
                await performMarkSeasonWatched()
            case .rateAndMark(let score, _):
                await performSaveScore(score)
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

    private func performSaveScore(_ score: Double) async {
        guard let outcome = await viewModel.saveUserScore(score) else { return }
        if let change = outcome.membershipChange, change.confirmation != nil {
            notice.show(
                change,
                using: lists,
                ratingKey: ratingKey(for: outcome),
                tvWatch: tvWatch,
                watchUndo: outcome.watchUndo
            )
        } else if outcome.episodesNewlyMarked > 0 {
            notice.presentWatch(
                outcome,
                ratingKey: ratingKey(for: outcome),
                fallbackMessage: "Season watched",
                using: lists,
                tvWatch: tvWatch
            )
        }
        await viewModel.reloadNextUp()
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

    private func episodes(_ episodes: [TVEpisodeSummary], seriesName: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("Episodes")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, DesignSpacing.lg)

            ForEach(episodes) { episode in
                let isContinueFocus = scrollToEpisodeNumber == episode.episodeNumber
                VStack(spacing: 0) {
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
                    }
                    .padding(.horizontal, DesignSpacing.lg)
                }
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
