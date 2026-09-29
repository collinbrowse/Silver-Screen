//
//  TVSeriesRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct TVSeriesRouteView: View {
    @State private var viewModel: TVSeriesViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let router: NavigationRouter

    init(
        seriesID: Int,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVSeriesViewModel(
                seriesID: seriesID,
                shows: shows,
                annotations: annotations,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.router = router
    }

    var body: some View {
        TVSeriesView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            router: router
        )
    }
}
