//
//  LibraryDetailRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct LibraryDetailRouteView: View {
    @State private var viewModel: LibraryDetailViewModel
    let lists: ListsRepository
    let imageLoader: ImageLoader
    let router: NavigationRouter

    init(
        listID: UUID,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: LibraryDetailViewModel(
                listID: listID,
                lists: lists,
                annotations: annotations,
                tvWatch: tvWatch
            )
        )
        self.lists = lists
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        LibraryDetailView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            router: router,
            lists: lists
        )
    }
}
