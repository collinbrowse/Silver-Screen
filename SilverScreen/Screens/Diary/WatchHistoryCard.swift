//
//  WatchHistoryCard.swift
//  SilverScreen
//
//  The Watch History card on a detail screen: the watch count and last day, opening the
//  title's watch history. The detail screen owns the view model (see
//  `WatchHistoryCardViewModel.refreshed`) and shows this only once there is history.
//

import SwiftUI

struct WatchHistoryCard: View {
    let viewModel: WatchHistoryCardViewModel
    /// The title's history screen.
    let route: Route

    var body: some View {
        SurfaceCard {
            NavigationLink(value: route) {
                WatchHistoryCardRow(
                    systemImage: "clock.arrow.circlepath",
                    title: "Watch History",
                    subtitle: viewModel.summary
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows every watch of this title")
        }
    }
}
