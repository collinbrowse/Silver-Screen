//
//  OnboardingSeenView.swift
//  SilverScreen
//
//  "What have you seen?" Tap a poster to put it on Watched, then rate it with
//  the stars under it or leave it unrated. Continue works at any time.
//

import SwiftUI

struct OnboardingSeenView: View {
    @Bindable var viewModel: OnboardingSeenViewModel
    let imageLoader: ImageLoader
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    header
                    OnboardingPosterGrid(
                        state: viewModel.displayed,
                        emptyTitle: viewModel.isSearching ? "No Matches" : "Nothing to Show",
                        emptyMessage: viewModel.isSearching
                            ? "Try another title."
                            : "Search for something you have seen.",
                        retry: retry
                    ) { title, width in
                        cell(title, width: width)
                    }
                }
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.bottom, DesignSpacing.lg)
            }
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .top) {
                if case .loaded(_, let activity) = viewModel.displayed {
                    LoadActivityBanner(activity: activity)
                }
            }
            .background(DesignTheme.canvas)
            .navigationSearch(text: $viewModel.searchText, prompt: "Search movies and shows")
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
                OnboardingBottomBar(title: "Continue", action: onContinue)
            }
        }
        .task { await viewModel.load() }
        .task(id: viewModel.searchText) {
            // Wait for typing to pause; a new keystroke cancels this task.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("What have you seen?")
                .font(DesignTypography.title)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Tap anything you have watched. Rate \(OnboardingSeenViewModel.ratingGoal) to get started.")
                .font(DesignTypography.body)
                .foregroundStyle(DesignTheme.textSecondary)
            ProgressView(value: viewModel.goalFraction) {
                Text(viewModel.goalText)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textSecondary)
            }
            .tint(DesignTheme.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rating goal")
            .accessibilityValue(viewModel.goalText)
        }
        .padding(.top, DesignSpacing.sm)
    }

    private func cell(_ title: OnboardingTitle, width: CGFloat) -> some View {
        let picked = viewModel.isPicked(title)
        return OnboardingPosterCell(
            title: title,
            width: width,
            isPicked: picked,
            pickedState: "Seen",
            unpickedState: "Not seen",
            actionHint: picked ? "Removes it from Watched." : "Adds it to Watched.",
            imageLoader: imageLoader,
            onTap: { Task { await viewModel.toggle(title) } }
        ) {
            if picked {
                OnboardingStarRating(
                    title: title.draft.title,
                    score: viewModel.score(for: title)
                ) { score in
                    Task { await viewModel.rate(title, score: score) }
                }
            }
        }
    }

    private func retry() async {
        if viewModel.isSearching {
            await viewModel.search()
        } else {
            await viewModel.reload()
        }
    }
}
