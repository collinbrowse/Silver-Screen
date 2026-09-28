//
//  RootTabView.swift
//  TheSilverScreen
//

import SwiftUI

struct RootTabView: View {
    @Bindable var router: AppRouter
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let listChanges: ListChangeNotice
    let annotations: AnnotationsRepository
    let awards: AwardsRepository
    let imageLoader: ImageLoader
    let libraryHomeViewModel: LibraryHomeViewModel

    @State private var browseViewModel: BrowseListViewModel
    @State private var searchViewModel: SearchViewModel

    init(
        router: AppRouter,
        movies: MovieRepository,
        shows: TVRepository,
        people: PersonRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        listChanges: ListChangeNotice,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        libraryHomeViewModel: LibraryHomeViewModel
    ) {
        self.router = router
        self.movies = movies
        self.shows = shows
        self.people = people
        self.lists = lists
        self.listsIndex = listsIndex
        self.listChanges = listChanges
        self.annotations = annotations
        self.awards = awards
        self.imageLoader = imageLoader
        self.libraryHomeViewModel = libraryHomeViewModel
        _browseViewModel = State(
            initialValue: BrowseListViewModel(movies: movies, shows: shows, annotations: annotations)
        )
        _searchViewModel = State(
            initialValue: SearchViewModel(
                movies: movies,
                shows: shows,
                people: people,
                annotations: annotations,
                awards: awards
            )
        )
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                BrowseTabRoot(
                    router: router.browse,
                    viewModel: browseViewModel,
                    imageLoader: imageLoader,
                    movies: movies,
                    shows: shows,
                    people: people,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    awards: awards
                )
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchTabRoot(
                    router: router.search,
                    viewModel: searchViewModel,
                    imageLoader: imageLoader,
                    movies: movies,
                    shows: shows,
                    people: people,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    awards: awards
                )
            }

            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryTabRoot(
                    router: router.favorites,
                    viewModel: libraryHomeViewModel,
                    imageLoader: imageLoader,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    awards: awards,
                    movies: movies,
                    shows: shows,
                    people: people
                )
            }
        }
        .environment(listChanges)
        .overlay(alignment: .bottom) {
            ListChangeBanner(notice: listChanges)
        }
    }
}

/// Confirmation after adding or removing a title. Undo sits above the tab bar.
private struct ListChangeBanner: View {
    @Bindable var notice: ListChangeNotice

    var body: some View {
        if let message = notice.message {
            HStack(spacing: DesignSpacing.md) {
                Text(message)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignSpacing.sm)
                Button("Undo") {
                    Task { await notice.undo() }
                }
                .font(DesignTypography.metadata.weight(.semibold))
                .frame(minHeight: 44)
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.bottom, 56)
            .accessibilityElement(children: .contain)
        }
    }
}

private struct BrowseTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: BrowseListViewModel
    let imageLoader: ImageLoader
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let annotations: AnnotationsRepository
    let awards: AwardsRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            BrowseListView(
                viewModel: viewModel,
                imageLoader: imageLoader,
                lists: lists,
                listsIndex: listsIndex,
                router: router
            )
            .navigationDestination(for: Route.self) { route in
                AppRouteDestination(
                    route: route,
                    movies: movies,
                    shows: shows,
                    people: people,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    awards: awards,
                    imageLoader: imageLoader,
                    router: router
                )
            }
        }
    }
}

private struct SearchTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: SearchViewModel
    let imageLoader: ImageLoader
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let annotations: AnnotationsRepository
    let awards: AwardsRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            SearchView(
                viewModel: viewModel,
                imageLoader: imageLoader,
                lists: lists,
                listsIndex: listsIndex,
                router: router
            )
            .navigationDestination(for: Route.self) { route in
                AppRouteDestination(
                    route: route,
                    movies: movies,
                    shows: shows,
                    people: people,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    awards: awards,
                    imageLoader: imageLoader,
                    router: router
                )
            }
        }
    }
}

private struct LibraryTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: LibraryHomeViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let annotations: AnnotationsRepository
    let awards: AwardsRepository
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            LibraryHomeView(viewModel: viewModel)
                .navigationDestination(for: Route.self) { route in
                    AppRouteDestination(
                        route: route,
                        movies: movies,
                        shows: shows,
                        people: people,
                        lists: lists,
                        listsIndex: listsIndex,
                        annotations: annotations,
                        awards: awards,
                        imageLoader: imageLoader,
                        router: router
                    )
                }
        }
    }
}
