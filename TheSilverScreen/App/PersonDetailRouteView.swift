//
//  PersonDetailRouteView.swift
//  TheSilverScreen
//

import SwiftUI

struct PersonDetailRouteView: View {
    @State private var viewModel: PersonDetailViewModel
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let imageLoader: ImageLoader
    let router: NavigationRouter

    init(
        personID: Int,
        people: PersonRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: PersonDetailViewModel(
                personID: personID,
                people: people,
                awards: awards
            )
        )
        self.lists = lists
        self.listsIndex = listsIndex
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        PersonDetailView(
            viewModel: viewModel,
            lists: lists,
            listsIndex: listsIndex,
            imageLoader: imageLoader,
            router: router
        )
    }
}
