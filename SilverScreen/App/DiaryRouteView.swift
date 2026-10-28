//
//  DiaryRouteView.swift
//  SilverScreen
//
//  Builds the diary screen, or one title's watch history, from the `DiaryContext` the
//  root installs, so the route table does not have to carry diary dependencies to every tab.
//

import SwiftUI

struct DiaryRouteView: View {
    let imageLoader: ImageLoader
    let router: NavigationRouter
    /// One title's history, or nil for the whole diary.
    var scope: DiaryScope?

    @Environment(DiaryContext.self) private var context: DiaryContext?

    var body: some View {
        if let context {
            DiaryView(
                viewModel: DiaryViewModel(context: context, scope: scope),
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
