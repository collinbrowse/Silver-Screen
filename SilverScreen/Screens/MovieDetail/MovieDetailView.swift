//
//  MovieDetailView.swift
//  SilverScreen
//

import SwiftUI

struct MovieDetailView: View {
    @State var viewModel: MovieDetailViewModel
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let imageLoader: ImageLoader
    var router: NavigationRouter?
    var showsToolbarFavorite: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var heroTransition
    @State private var selectedBackdropID: String?
    @State private var playingTrailer: MediaTrailer?
    @State private var loadingTrailerID: String?
    /// True while the iPhone Duo's fold crosses the page; see `metadataBlock`.
    @State private var isFolded = false

    private let portraitCardWidth: CGFloat = 140

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
                        title: "Movie Unavailable",
                        message: "This movie could not be shown.",
                        systemImage: "film"
                    )
                case .loaded(let content, let activity):
                    loadedBody(content: content, activity: activity)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.retry()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .toolbar {
            if showsToolbarFavorite, case .loaded(let content, _) = viewModel.state {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    WatchedToggleButton(
                        draft: content.detail.listItem(),
                        lists: lists,
                        index: listsIndex,
                        chrome: false
                    ) {
                        viewModel.noteListSaveFailed()
                    }
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
        .fullScreenCover(item: showsToolbarFavorite ? fullscreenBinding : .constant(nil)) { selection in
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
            return content.detail.title
        }
        return ""
    }

    @ViewBuilder
    private func loadedBody(content: MovieDetailContent, activity: LoadActivity) -> some View {
        ScrollViewReader { proxy in
            loadedScroll(content: content, activity: activity, scrollTo: { id in
                proxy.scrollTo(id, anchor: .top)
                })
        }
    }

    private func loadedScroll(
        content: MovieDetailContent,
        activity: LoadActivity,
        scrollTo: @escaping (String) -> Void
    ) -> some View {
        let bleedsToTop = content.images?.items.isEmpty == false
        // Read here, in the view's own body, so a fold change re-renders the page; a
        // state read only inside the width reader's closure would not.
        let pageIsFolded = isFolded
        return GeometryReader { proxy in
            detailScroll(
                content: content,
                activity: activity,
                scrollTo: scrollTo,
                width: proxy.size.width,
                pageIsFolded: pageIsFolded
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .heroStatusBarBleed(enabled: bleedsToTop)
        .scrollingInlineTitle(navigationTitle, showsToolbarBackground: !bleedsToTop)
    }

    private func detailScroll(
        content: MovieDetailContent,
        activity: LoadActivity,
        scrollTo: @escaping (String) -> Void,
        width: CGFloat,
        pageIsFolded: Bool
    ) -> some View {
        let twoColumns = DetailLayoutMetrics.usesTwoColumns(
            forWidth: width,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        let contentWidth = DetailLayoutMetrics.contentWidth(forWidth: width, twoColumns: twoColumns)
        let sectionsInPanes = twoColumns && pageIsFolded
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                if sectionsInPanes {
                    hero(content, twoColumns: twoColumns, part: .backdrop)
                    hingePanes(content, scrollTo: scrollTo, contentWidth: contentWidth)
                } else {
                    hero(content, twoColumns: twoColumns, part: .all)
                    metadataBlock(
                        content,
                        scrollTo: scrollTo,
                        twoColumns: twoColumns,
                        contentWidth: contentWidth
                    )
                    carousels(content)
                    if let reviews = content.reviews {
                        reviewsSection(reviews, scrollTo: scrollTo, columns: twoColumns ? 2 : 1)
                    }
                }
                if !content.detail.streamingProviders.isEmpty {
                    JustWatchAttributionFooter()
                        .padding(.horizontal, DesignSpacing.lg)
                }
            }
            .padding(.bottom, DesignSpacing.lg)
            .frame(width: contentWidth)
            .frame(maxWidth: .infinity)
            .coordinateSpace(.named("detailScroll"))
        }
        .onFoldSplitChange { isFolded = $0 != nil }
        .overlay(alignment: .top) {
            if case .failed(let error) = activity {
                Text("\(error.title): \(error.message)")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(DesignSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .accessibilityLabel("\(error.title). \(error.message)")
            }
        }
    }

    /// Rating, storyline, facts, and awards, in that order on a phone. On a wide page
    /// awards take the side column and facts join the main one, since a long awards
    /// card already outweighs the rest; with no awards, facts take the side column.
    private func metadataBlock(
        _ content: MovieDetailContent,
        scrollTo: @escaping (String) -> Void,
        twoColumns: Bool,
        contentWidth: CGFloat
    ) -> some View {
        let hasAwards = !viewModel.awardRows.isEmpty
        return DetailColumns(twoColumns: twoColumns, contentWidth: contentWidth) {
            ratingCard(content)
            storyline(content, scrollTo: scrollTo)
            if hasAwards {
                factsCard(content)
            }
        } secondary: {
            if hasAwards {
                AwardRowsSection(rows: viewModel.awardRows)
            } else {
                factsCard(content)
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    /// The page below the backdrop while the iPhone Duo's hinge is bent: the leading
    /// pane holds the title, facts, rating, storyline, and reviews; the trailing pane
    /// holds awards and the carousels, starting beside the title.
    private func hingePanes(
        _ content: MovieDetailContent,
        scrollTo: @escaping (String) -> Void,
        contentWidth: CGFloat
    ) -> some View {
        DetailColumns(twoColumns: true, contentWidth: contentWidth) {
            hero(content, twoColumns: true, part: .identity)
                .inPane()
            factsCard(content)
            ratingCard(content)
            storyline(content, scrollTo: scrollTo)
            if let reviews = content.reviews {
                reviewsSection(reviews, scrollTo: scrollTo, columns: 1)
                    .inPane()
            }
        } secondary: {
            if !viewModel.awardRows.isEmpty {
                AwardRowsSection(rows: viewModel.awardRows)
            }
            carousels(content)
                .inPane()
        }
        .detailColumnsInset(hingePanes: true)
    }

    private func hero(_ content: MovieDetailContent, twoColumns: Bool, part: DetailHeroPart) -> some View {
        DetailHero(
            title: content.detail.title,
            posterPath: content.detail.posterPath,
            images: content.images?.items ?? [],
            selectedImageID: $selectedBackdropID,
            imageLoader: imageLoader,
            transitionNamespace: heroTransition,
            onOpenPoster: { viewModel.openPoster() },
            onOpenImage: { viewModel.openImages(initialID: $0) },
            streamingProviders: content.detail.streamingProviders,
            aspectRatio: DetailLayoutMetrics.heroAspectRatio(twoColumns: twoColumns),
            part: part
        ) {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                if !content.heroMetadataLine.isEmpty {
                    Text(content.heroMetadataLine)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(content.heroMetadataAccessibilityLabel)
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

    private func ratingCard(_ content: MovieDetailContent) -> some View {
        TMDBRatingCard(
            formattedRating: content.formattedRating,
            accessibilityLabel: content.ratingAccessibilityLabel,
            formattedUserScore: content.formattedUserScore,
            userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
            onEdit: { viewModel.openAnnotationEditor() }
        )
    }

    private func storyline(_ content: MovieDetailContent, scrollTo: @escaping (String) -> Void) -> some View {
        MediaDescriptionSection(
            overview: content.detail.overview,
            note: content.userNote,
            notedOn: content.formattedNotedOn,
            onEdit: { viewModel.openAnnotationEditor() },
            scrollTo: scrollTo
        )
    }

    @ViewBuilder
    private func carousels(_ content: MovieDetailContent) -> some View {
        if let cast = content.cast {
            castCarousel(cast)
        }
        if let crew = content.crew {
            crewCarousel(crew)
        }
        if let similar = content.similar {
            similarCarousel(similar)
        }
        if let collection = content.collection {
            collectionCarousel(collection)
        }
    }

    // MARK: - Carousels

    private func castCarousel(
        _ section: MovieDetailContent.CastSection
    ) -> some View {
        DetailCarousel(title: "Top Billed Cast") {
            ForEach(section.members) { member in
                Button {
                    router?.push(.person(id: member.personID))
                } label: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        RemoteImageView(
                            path: member.profilePath,
                            kind: .profile,
                            width: portraitCardWidth,
                            aspectRatio: 2 / 3,
                            imageLoader: imageLoader,
                            placeholderSystemImage: "person.fill"
                        )
                        .carouselCard(width: portraitCardWidth, aspectRatio: 2 / 3)

                        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                            Text(member.name)
                                .font(DesignTypography.metadata.weight(.semibold))
                                .foregroundStyle(DesignTheme.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(member.character.isEmpty ? " " : member.character)
                                .font(DesignTypography.chip)
                                .foregroundStyle(DesignTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(castAccessibilityLabel(member))
                    }
                    .frame(width: portraitCardWidth, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(router == nil)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(router == nil ? [] : .isButton)
            }
        }
    }

    private func crewCarousel(
        _ section: MovieDetailContent.CrewSection
    ) -> some View {
        DetailCarousel(title: "Directors & Writers") {
            ForEach(section.people) { person in
                Button {
                    router?.push(.person(id: person.id))
                } label: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        RemoteImageView(
                            path: person.profilePath,
                            kind: .profile,
                            width: portraitCardWidth,
                            aspectRatio: 2 / 3,
                            imageLoader: imageLoader,
                            placeholderSystemImage: "person.fill"
                        )
                        .carouselCard(width: portraitCardWidth, aspectRatio: 2 / 3)

                        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                            Text(person.name)
                                .font(DesignTypography.metadata.weight(.semibold))
                                .foregroundStyle(DesignTheme.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(person.rolesLabel)
                                .font(DesignTypography.chip)
                                .foregroundStyle(DesignTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(person.name), \(person.rolesLabel)")
                    }
                    .frame(width: portraitCardWidth, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(router == nil)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(router == nil ? [] : .isButton)
            }
        }
    }

    private func similarCarousel(
        _ section: MovieDetailContent.SimilarSection
    ) -> some View {
        DetailCarousel(title: "More Like This") {
            ForEach(section.items) { item in
                similarMovieCell(item)
            }
        }
    }

    private func collectionCarousel(
        _ section: MovieDetailContent.CollectionSection
    ) -> some View {
        DetailCarousel(title: section.title, onTitle: {
            router?.push(.collection(id: section.id))
            }) {
            ForEach(section.movies) { movie in
                moviePosterCell(
                    movie: movie,
                    subtitle: nil
                )
            }
        }
    }

    private func similarMovieCell(
        _ item: MovieDetailContent.SimilarSection.Item
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            MoviePosterView(
                posterPath: item.movie.posterPath,
                imageLoader: imageLoader,
                width: portraitCardWidth
            )
            .overlay(alignment: .topTrailing) {
                CarouselRatingBadge(
                    formattedScore: viewModel.userScore(forMovieID: item.id),
                    isWatched: listsIndex.isOnWatched(item.movie.listItem().itemKey)
                )
                .padding(DesignSpacing.xs)
            }

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(item.movie.title)
                    .font(DesignTypography.metadata.weight(.semibold))
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.genreNames.isEmpty {
                    Text(item.genreNames.joined(separator: ", "))
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if item.formattedReleaseDate != "Not available" {
                    Text(item.formattedReleaseDate)
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(similarAccessibilityLabel(item))
            .accessibilityAddTraits(router == nil ? [] : .isButton)
        }
        .frame(width: portraitCardWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            router?.push(.movieDetail(id: item.id))
        }
        .accessibilityElement(children: .contain)
    }

    private func moviePosterCell(
        movie: Movie,
        subtitle: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            MoviePosterView(
                posterPath: movie.posterPath,
                imageLoader: imageLoader,
                width: portraitCardWidth
            )
            .overlay(alignment: .topTrailing) {
                CarouselRatingBadge(
                    formattedScore: viewModel.userScore(forMovieID: movie.id),
                    isWatched: listsIndex.isOnWatched(movie.listItem().itemKey)
                )
                .padding(DesignSpacing.xs)
            }

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(movie.title)
                    .font(DesignTypography.metadata.weight(.semibold))
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(movie.title)
            .accessibilityAddTraits(router == nil ? [] : .isButton)
        }
        .frame(width: portraitCardWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            router?.push(.movieDetail(id: movie.id))
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Reviews

    private func reviewsSection(
        _ section: MovieDetailContent.ReviewsSection,
        scrollTo: @escaping (String) -> Void,
        columns: Int
    ) -> some View {
        ReviewPageList(
            items: section.items,
            hasMore: section.hasMore,
            totalCount: section.totalCount,
            isLoadingPage: section.isLoadingPage,
            pageError: section.pageError,
            loadMore: { await viewModel.loadMoreReviews() },
            scrollTo: scrollTo,
            columns: columns
        )
    }

    // MARK: - Story 1 metadata

    private func factsCard(_ content: MovieDetailContent) -> some View {
        SurfaceCard {
            let stack = dynamicTypeSize.isAccessibilitySize
            Group {
                if stack {
                    VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                        factCell(label: "Budget", value: content.formattedBudget, accessibility: content.budgetAccessibilityLabel)
                        Divider()
                        factCell(label: "Revenue", value: content.formattedRevenue, accessibility: content.revenueAccessibilityLabel)
                        Divider()
                        factCell(label: "Release Date", value: content.formattedReleaseDate, accessibility: content.formattedReleaseDate)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            factCell(label: "Budget", value: content.formattedBudget, accessibility: content.budgetAccessibilityLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle()
                                .fill(DesignTheme.separator.opacity(0.35))
                                .frame(width: 0.5)
                                .padding(.vertical, DesignSpacing.xs)
                            factCell(label: "Revenue", value: content.formattedRevenue, accessibility: content.revenueAccessibilityLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, DesignSpacing.lg)
                        }
                        Divider()
                            .padding(.vertical, DesignSpacing.md)
                        factCell(label: "Release Date", value: content.formattedReleaseDate, accessibility: content.formattedReleaseDate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func factCell(label: String, value: String, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(label.uppercased())
                .font(DesignTypography.factLabel)
                .foregroundStyle(DesignTheme.textMuted)
                .tracking(0.6)
            Text(value)
                .font(DesignTypography.factValue)
                .foregroundStyle(DesignTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(accessibility)")
    }

    private func castAccessibilityLabel(_ member: CastMember) -> String {
        if member.character.isEmpty {
            return member.name
        }
        return "\(member.name) as \(member.character)"
    }

    private func similarAccessibilityLabel(_ item: MovieDetailContent.SimilarSection.Item) -> String {
        var parts = [item.movie.title]
        if !item.genreNames.isEmpty {
            parts.append(item.genreNames.joined(separator: ", "))
        }
        if item.formattedReleaseDate != "Not available" {
            parts.append(item.formattedReleaseDate)
        }
        return parts.joined(separator: ", ")
    }
}
