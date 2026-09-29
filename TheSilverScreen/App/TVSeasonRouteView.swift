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
    let router: NavigationRouter
    let seriesID: Int
    let seasonNumber: Int

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVSeasonViewModel(
                seriesID: seriesID,
                seriesName: seriesName,
                seasonNumber: seasonNumber,
                shows: shows,
                annotations: annotations,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.router = router
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
    }

    var body: some View {
        TVSeasonView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            router: router,
            seriesID: seriesID,
            seasonNumber: seasonNumber
        )
    }
}
