//
//  TVSeasonRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct TVSeasonRouteView: View {
    @State private var viewModel: TVSeasonViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let tvWatch: TVWatchRepository
    let router: NavigationRouter
    let seriesID: Int
    let seasonNumber: Int
    /// When set, scroll the episode list so this episode is at the top after load.
    let scrollToEpisodeNumber: Int?

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        seriesSnapshot: SeriesListSnapshot,
        scrollToEpisodeNumber: Int? = nil,
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
            initialValue: TVSeasonViewModel(
                seriesID: seriesID,
                seriesName: seriesName,
                seasonNumber: seasonNumber,
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
        self.router = router
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.scrollToEpisodeNumber = scrollToEpisodeNumber
    }

    var body: some View {
        TVSeasonView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            tvWatch: tvWatch,
            router: router,
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            scrollToEpisodeNumber: scrollToEpisodeNumber
        )
    }
}
