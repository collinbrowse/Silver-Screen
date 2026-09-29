//
//  CollectionRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct CollectionRouteView: View {
    @State private var viewModel: CollectionViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let router: NavigationRouter

    init(
        collectionID: Int,
        movies: MovieRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: CollectionViewModel(
                collectionID: collectionID,
                movies: movies,
                annotations: annotations
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.router = router
    }

    var body: some View {
        CollectionView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            router: router
        )
    }
}
