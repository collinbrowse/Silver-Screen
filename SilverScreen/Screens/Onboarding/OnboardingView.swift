//
//  OnboardingView.swift
//  SilverScreen
//
//  The full-screen cover over the tabs on first launch. Each presentation gets
//  a fresh view model, so reopening from the Library starts at Welcome again.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    let imageLoader: ImageLoader

    init(viewModel: OnboardingViewModel, imageLoader: ImageLoader) {
        _viewModel = State(initialValue: viewModel)
        self.imageLoader = imageLoader
    }

    var body: some View {
        Group {
            switch viewModel.step {
                case .welcome:
                    OnboardingWelcomeView(
                        onGetStarted: viewModel.getStarted,
                        onSkip: viewModel.skip
                    )
                case .seen:
                    OnboardingSeenView(
                        viewModel: viewModel.seen,
                        imageLoader: imageLoader,
                        onBack: viewModel.back,
                        onSkip: viewModel.skip,
                        onContinue: viewModel.continueToWatchlist
                    )
                case .watchlist:
                    OnboardingWatchlistView(
                        viewModel: viewModel.watchlist,
                        excludedKeys: viewModel.seen.pickedKeys,
                        imageLoader: imageLoader,
                        onBack: viewModel.back,
                        onSkip: viewModel.skip,
                        onDone: { Task { await viewModel.finish() } }
                    )
            }
        }
        .animation(.default, value: viewModel.step)
    }
}
