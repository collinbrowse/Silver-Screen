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
    let tvWatch: TVWatchRepository
    let seriesID: Int
    let seriesName: String
    let seasonNumber: Int
    let episodeNumber: Int
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
        tvWatch: TVWatchRepository,
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
                tvWatch: tvWatch,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.tvWatch = tvWatch
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.router = router
    }

    var body: some View {
        TVEpisodeView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            tvWatch: tvWatch,
            seriesID: seriesID,
            seriesName: seriesName,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            router: router
        )
    }
}
