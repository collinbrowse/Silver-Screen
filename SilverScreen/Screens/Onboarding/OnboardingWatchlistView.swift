//
//  OnboardingWatchlistView.swift
//  SilverScreen
//
//  "What do you want to watch?" Upcoming, in theaters, on the air, and popular,
//  minus everything marked seen. A tap adds to Watchlist; Done lands on the Library.
//

import SwiftUI

struct OnboardingWatchlistView: View {
    let viewModel: OnboardingWatchlistViewModel
    /// Seen picks to leave out of this grid.
    let excludedKeys: Set<String>
    let imageLoader: ImageLoader
    let onBack: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    header
                    OnboardingPosterGrid(
                        state: viewModel.state,
                        emptyTitle: "Nothing to Show",
                        emptyMessage: "You can add titles to your Watchlist from Browse and Search.",
                        retry: { await viewModel.reload() }
                    ) { title, width in
                        cell(title, width: width)
                    }
                }
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.bottom, DesignSpacing.lg)
            }
            .overlay(alignment: .top) {
                if case .loaded(_, let activity) = viewModel.state {
                    LoadActivityBanner(activity: activity)
                }
            }
            .background(DesignTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip", action: onSkip)
                        .accessibilityHint("Closes setup. Titles you picked stay saved.")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingBottomBar(title: "Done", action: onDone)
            }
        }
        .task(id: excludedKeys) {
            await viewModel.load(excluding: excludedKeys)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("What do you want to watch?")
                .font(DesignTypography.title)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Tap anything you want to see. It goes on your Watchlist.")
                .font(DesignTypography.body)
                .foregroundStyle(DesignTheme.textSecondary)
        }
        .padding(.top, DesignSpacing.sm)
    }

    private func cell(_ title: OnboardingTitle, width: CGFloat) -> some View {
        let picked = viewModel.isPicked(title)
        return OnboardingPosterCell(
            title: title,
            width: width,
            isPicked: picked,
            pickedState: "On Watchlist",
            unpickedState: "Not on Watchlist",
            actionHint: picked ? "Removes it from Watchlist." : "Adds it to Watchlist.",
            imageLoader: imageLoader,
            onTap: { Task { await viewModel.toggle(title) } }
        ) {
            EmptyView()
        }
    }
}
