//
//  TVEpisodeRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct TVEpisodeRouteView: View {
    @State private var viewModel: TVEpisodeViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let seriesID: Int
    let seriesName: String
    let seasonNumber: Int
    let router: NavigationRouter

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        episodeNumber: Int,
        seriesSnapshot: SeriesListSnapshot,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVEpisodeViewModel(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                seriesSnapshot: seriesSnapshot,
                shows: shows,
                annotations: annotations,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.router = router
    }

    var body: some View {
        TVEpisodeView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            seriesID: seriesID,
            seriesName: seriesName,
            seasonNumber: seasonNumber,
            router: router
        )
    }
}
