//
//  BrowseTabRoot.swift
//  TheSilverScreen
//

import SwiftUI

struct BrowseTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: BrowseListViewModel
    let imageLoader: ImageLoader
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let annotations: AnnotationsRepository
    let tvWatch: TVWatchRepository
    let awards: AwardsRepository

    var body: some View {
        NavigationStack(path: $router.path) {
            BrowseListView(
                viewModel: viewModel,
                imageLoader: imageLoader,
                lists: lists,
                listsIndex: listsIndex,
                shows: shows,
                tvWatch: tvWatch,
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
                    tvWatch: tvWatch,
                    awards: awards,
                    imageLoader: imageLoader,
                    router: router
                )
            }
        }
    }
}
