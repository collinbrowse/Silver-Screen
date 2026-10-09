//
//  SearchTabRoot.swift
//  TheSilverScreen
//

import SwiftUI

struct SearchTabRoot: View {
    @Bindable var router: NavigationRouter
    @Bindable var viewModel: SearchViewModel
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
            SearchView(
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
