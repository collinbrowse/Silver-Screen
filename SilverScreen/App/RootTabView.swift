//
//  RootTabView.swift
//  SilverScreen
//

import SwiftUI

struct RootTabView: View {
    @Bindable var router: AppRouter
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    @Bindable var listChanges: ListChangeNotice
    let annotations: AnnotationsRepository
    let tvWatch: TVWatchRepository
    let awards: AwardsRepository
    let imageLoader: ImageLoader
    let libraryHomeViewModel: LibraryHomeViewModel
    let settings: SettingsContext
    let reviewPrompter: ReviewPrompter

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
        tvWatch: TVWatchRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        libraryHomeViewModel: LibraryHomeViewModel,
        settings: SettingsContext,
        reviewPrompter: ReviewPrompter
    ) {
        self.router = router
        self.movies = movies
        self.shows = shows
        self.people = people
        self.lists = lists
        self.listsIndex = listsIndex
        self.listChanges = listChanges
        self.annotations = annotations
        self.tvWatch = tvWatch
        self.awards = awards
        self.imageLoader = imageLoader
        self.libraryHomeViewModel = libraryHomeViewModel
        self.settings = settings
        self.reviewPrompter = reviewPrompter
        _browseViewModel = State(
            initialValue: BrowseListViewModel(
                movies: movies,
                shows: shows,
                annotations: annotations,
                tvWatch: tvWatch
            )
        )
        _searchViewModel = State(
            initialValue: SearchViewModel(
                movies: movies,
                shows: shows,
                people: people,
                annotations: annotations,
                tvWatch: tvWatch,
                awards: awards
            )
        )
    }

    private var toastAnnotationEditorBinding: Binding<AnnotationEditorSession?> {
        Binding(
            get: { listChanges.annotationEditor },
            set: { newValue in
                if newValue == nil {
                    listChanges.dismissRatingEditor()
                }
            }
        )
    }

    var body: some View {
        // Read `message` here so RootTabView observes ListChangeNotice. The overlay
        // alone (child @Bindable) can miss updates when only the notice changes.
        let bannerMessage = listChanges.message
        tabs(showsBanner: bannerMessage != nil)
            .environment(listChanges)
            .sheet(item: toastAnnotationEditorBinding) { session in
                AnnotationEditorSheet(
                    title: session.title,
                    score: session.score,
                    note: session.note,
                    canClear: session.canClear,
                    onSave: { await listChanges.saveRatingAnnotation(score: $0, note: $1) },
                    onClear: { await listChanges.clearRatingAnnotation() }
                )
            }
            .modifier(ReviewPromptPresenter(prompter: reviewPrompter))
    }

    /// On Mac this iOS app keeps a tab bar and does not minimize it. Hiding that
    /// bar during search lays the system search field out through `UIScreen`
    /// focus, which UIKit rejects and terminates the process. The search field
    /// itself is a text field on Mac; see `MacSearchField`.
    ///
    /// Elsewhere the tabs adapt to the window's width: a regular-width window (iPad,
    /// a wide foldable screen) can open them as a sidebar, and a compact one keeps the
    /// bottom tab bar. Each tab keeps its own `NavigationStack` either way.
    @ViewBuilder
    private func tabs(showsBanner: Bool) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            tabView(showsBanner: showsBanner)
                .tabViewStyle(.tabBarOnly)
                .tabBarMinimizeBehavior(.never)
        } else {
            tabView(showsBanner: showsBanner)
                .tabViewStyle(.sidebarAdaptable)
        }
    }

    /// Each tab hosts the list-change banner itself; see `ListChangeBannerHost`.
    private func tabView(showsBanner: Bool) -> some View {
        let banner = ListChangeBannerHost(notice: listChanges, isShowing: showsBanner)
        return TabView(selection: $router.selectedTab) {
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
                    tvWatch: tvWatch,
                    awards: awards
                )
                .modifier(banner)
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
                    tvWatch: tvWatch,
                    awards: awards
                )
                .modifier(banner)
            }

            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryTabRoot(
                    router: router.favorites,
                    viewModel: libraryHomeViewModel,
                    imageLoader: imageLoader,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    tvWatch: tvWatch,
                    awards: awards,
                    movies: movies,
                    shows: shows,
                    people: people,
                    settings: settings
                )
                .modifier(banner)
            }
        }
    }
}
