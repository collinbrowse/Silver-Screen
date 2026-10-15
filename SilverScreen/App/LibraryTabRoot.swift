//
//  LibraryTabRoot.swift
//  SilverScreen
//

import SwiftUI

struct LibraryTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: LibraryHomeViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let annotations: AnnotationsRepository
    let tvWatch: TVWatchRepository
    let awards: AwardsRepository
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let settings: SettingsContext

    var body: some View {
        NavigationStack(path: $router.path) {
            LibraryHomeView(viewModel: viewModel, imageLoader: imageLoader, settings: settings)
                .navigationDestination(for: Route.self) { route in
                    AppRouteDestination(
                        route: route,
                        movies: movies,
                        shows: shows,
                        people: people,
                        lists: lists,
                        listsIndex: listsIndex,
                        annotations: annotations,
                        tvWatch: tvWatch,
                        awards: awards,
                        imageLoader: imageLoader,
                        router: router
                    )
                }
        }
    }
}
