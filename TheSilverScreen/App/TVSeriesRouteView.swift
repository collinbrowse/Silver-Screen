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
    let shows: TVRepository
    let tvWatch: TVWatchRepository
    let router: NavigationRouter

    init(
        seriesID: Int,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVSeriesViewModel(
                seriesID: seriesID,
                shows: shows,
                annotations: annotations,
                lists: lists,
                tvWatch: tvWatch,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.shows = shows
        self.tvWatch = tvWatch
        self.router = router
    }

    var body: some View {
        TVSeriesView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            shows: shows,
            tvWatch: tvWatch,
            router: router
        )
    }
}
