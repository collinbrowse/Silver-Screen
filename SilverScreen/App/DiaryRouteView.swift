//
//  DiaryRouteView.swift
//  SilverScreen
//
//  Builds the diary screen from the `DiaryContext` the root installs, so the route
//  table does not have to carry diary dependencies to every tab.
//

import SwiftUI

struct DiaryRouteView: View {
    let imageLoader: ImageLoader
    let router: NavigationRouter

    @Environment(DiaryContext.self) private var context: DiaryContext?

    var body: some View {
        if let context {
            DiaryView(
                viewModel: DiaryViewModel(context: context),
                imageLoader: imageLoader,
                router: router
            )
        } else {
            EmptyStateView(
                title: "Diary Unavailable",
                message: "The diary could not be opened.",
                systemImage: "book.closed"
            )
        }
    }
}
