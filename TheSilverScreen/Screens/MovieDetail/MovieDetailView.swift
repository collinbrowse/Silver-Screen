//
//  MovieDetailView.swift
//  TheSilverScreen
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
        return GeometryReader { proxy in
            detailScroll(
                content: content,
                activity: activity,
                scrollTo: scrollTo,
                width: proxy.size.width
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
        width: CGFloat
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                DetailHero(
                    title: content.detail.title,
                    posterPath: content.detail.posterPath,
                    images: content.images?.items ?? [],
                    selectedImageID: $selectedBackdropID,
                    imageLoader: imageLoader,
                    transitionNamespace: heroTransition,
                    onOpenPoster: { viewModel.openPoster() },
                    onOpenImage: { viewModel.openImages(initialID: $0) },
                    genreNames: content.detail.genres.map(\.name)
                ) {
                    if !content.detail.trailers.isEmpty {
                        MediaMetadataPills(
                            trailers: content.detail.trailers,
                            loadingTrailerID: loadingTrailerID,
                            playTrailer: { presentTrailer($0, loadingID: $loadingTrailerID, selection: $playingTrailer) }
                        )
                    }
                }

                metadataBlock(content)

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
                if let reviews = content.reviews {
                    reviewsSection(reviews, scrollTo: scrollTo)
                }
            }
            .padding(.bottom, DesignSpacing.lg)
            .frame(width: min(width, 700))
            .frame(maxWidth: .infinity)
            .coordinateSpace(.named("detailScroll"))
        }
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

    private func metadataBlock(_ content: MovieDetailContent) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xl) {
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
            factsCard(content)
            if !viewModel.awardRows.isEmpty {
                AwardRowsSection(rows: viewModel.awardRows)
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
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
                .overlay(alignment: .topTrailing) {
                    ListMembershipButton(
                        draft: member.listItem(),
                        lists: lists,
                        index: listsIndex
                    ) {
                        viewModel.noteListSaveFailed()
                    }
                    .padding(DesignSpacing.xs)
                }
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
                .overlay(alignment: .topTrailing) {
                    listControl(person.listItem())
                    .padding(DesignSpacing.xs)
                }
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
                listControl(item.movie.listItem())
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
                listControl(movie.listItem())
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

    private func listControl(_ draft: ListItemDraft) -> some View {
        ListMembershipButton(draft: draft, lists: lists, index: listsIndex) {
            viewModel.noteListSaveFailed()
        }
    }

    private func reviewsSection(
        _ section: MovieDetailContent.ReviewsSection,
        scrollTo: @escaping (String) -> Void
    ) -> some View {
        ReviewPageList(
            items: section.items,
            hasMore: section.hasMore,
            totalCount: section.totalCount,
            isLoadingPage: section.isLoadingPage,
            pageError: section.pageError,
            loadMore: { await viewModel.loadMoreReviews() },
            scrollTo: scrollTo
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
