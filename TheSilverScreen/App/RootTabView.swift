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
        tabs
            .environment(listChanges)
            .overlay(alignment: .bottom) {
                ListChangeBanner(notice: listChanges)
            }
    }

    /// On Mac this iOS app keeps a tab bar and does not minimize it. Hiding that
    /// bar during search lays the system search field out through `UIScreen`
    /// focus, which UIKit rejects and terminates the process. The search field
    /// itself is a text field on Mac; see `MacSearchField`.
    @ViewBuilder
    private var tabs: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            tabView
                .tabViewStyle(.tabBarOnly)
                .tabBarMinimizeBehavior(.never)
        } else {
            tabView
        }
    }

    private var tabView: some View {
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
    }
}
