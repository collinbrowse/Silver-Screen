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
    let favorites: FavoritesRepository
    let favoritesIndex: FavoritesIndex
    let annotations: AnnotationsRepository
    let imageLoader: ImageLoader
    let favoritesListViewModel: FavoritesListViewModel

    @State private var browseViewModel: BrowseListViewModel
    @State private var searchViewModel: SearchViewModel

    init(
        router: AppRouter,
        movies: MovieRepository,
        shows: TVRepository,
        people: PersonRepository,
        favorites: FavoritesRepository,
        favoritesIndex: FavoritesIndex,
        annotations: AnnotationsRepository,
        imageLoader: ImageLoader,
        favoritesListViewModel: FavoritesListViewModel
    ) {
        self.router = router
        self.movies = movies
        self.shows = shows
        self.people = people
        self.favorites = favorites
        self.favoritesIndex = favoritesIndex
        self.annotations = annotations
        self.imageLoader = imageLoader
        self.favoritesListViewModel = favoritesListViewModel
        _browseViewModel = State(
            initialValue: BrowseListViewModel(movies: movies, shows: shows, annotations: annotations)
        )
        _searchViewModel = State(
            initialValue: SearchViewModel(
                movies: movies,
                shows: shows,
                people: people,
                annotations: annotations
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
                    favorites: favorites,
                    favoritesIndex: favoritesIndex,
                    annotations: annotations
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
                    favorites: favorites,
                    favoritesIndex: favoritesIndex,
                    annotations: annotations
                )
            }

            Tab("Favorites", systemImage: "heart", value: AppTab.favorites) {
                FavoritesTabRoot(
                    router: router.favorites,
                    viewModel: favoritesListViewModel,
                    imageLoader: imageLoader,
                    favorites: favorites,
                    favoritesIndex: favoritesIndex,
                    annotations: annotations,
                    movies: movies,
                    shows: shows,
                    people: people
                )
            }
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
    let favorites: FavoritesRepository
    let favoritesIndex: FavoritesIndex
    let annotations: AnnotationsRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            BrowseListView(
                viewModel: viewModel,
                imageLoader: imageLoader,
                favorites: favorites,
                favoritesIndex: favoritesIndex,
                router: router
            )
            .navigationDestination(for: Route.self) { route in
                AppRouteDestination(
                    route: route,
                    movies: movies,
                    shows: shows,
                    people: people,
                    favorites: favorites,
                    favoritesIndex: favoritesIndex,
                    annotations: annotations,
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
    let favorites: FavoritesRepository
    let favoritesIndex: FavoritesIndex
    let annotations: AnnotationsRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            SearchView(
                viewModel: viewModel,
                imageLoader: imageLoader,
                favorites: favorites,
                favoritesIndex: favoritesIndex,
                router: router
            )
            .navigationDestination(for: Route.self) { route in
                AppRouteDestination(
                    route: route,
                    movies: movies,
                    shows: shows,
                    people: people,
                    favorites: favorites,
                    favoritesIndex: favoritesIndex,
                    annotations: annotations,
                    imageLoader: imageLoader,
                    router: router
                )
            }
        }
    }
}

private struct FavoritesTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: FavoritesListViewModel
    let imageLoader: ImageLoader
    let favorites: FavoritesRepository
    let favoritesIndex: FavoritesIndex
    let annotations: AnnotationsRepository
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            FavoritesListView(
                viewModel: viewModel,
                imageLoader: imageLoader
            )
            .navigationTitle("Favorites")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: Route.self) { route in
                AppRouteDestination(
                    route: route,
                    movies: movies,
                    shows: shows,
                    people: people,
                    favorites: favorites,
                    favoritesIndex: favoritesIndex,
                    annotations: annotations,
                    imageLoader: imageLoader,
                    router: router
                )
            }
        }
    }
}
