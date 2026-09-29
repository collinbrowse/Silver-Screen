//
//  MovieDetailRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct MovieDetailRouteView: View {
    @State private var viewModel: MovieDetailViewModel
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let imageLoader: ImageLoader
    let router: NavigationRouter

    init(
        movieID: Int,
        movies: MovieRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: MovieDetailViewModel(
                movieID: movieID,
                movies: movies,
                annotations: annotations,
                lists: lists,
                awards: awards
            )
        )
        self.lists = lists
        self.listsIndex = listsIndex
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        MovieDetailView(
            viewModel: viewModel,
            lists: lists,
            listsIndex: listsIndex,
            imageLoader: imageLoader,
            router: router
        )
    }
}
