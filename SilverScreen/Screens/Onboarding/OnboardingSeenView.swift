//
//  OnboardingSeenView.swift
//  SilverScreen
//
//  "What have you seen?" Tap a poster to put it on Watched, then rate it from
//  the chip under it or leave it unrated. Continue works at any time.
//

import SwiftUI

struct OnboardingSeenView: View {
    @Bindable var viewModel: OnboardingSeenViewModel
    let imageLoader: ImageLoader
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    /// The picked title whose rating sheet is open.
    @State private var rating: OnboardingTitle?

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
            .sheet(item: $rating) { title in
                AnnotationEditorSheet(
                    title: title.draft.title,
                    score: viewModel.score(for: title),
                    note: viewModel.note(for: title) ?? "",
                    canClear: viewModel.score(for: title) != nil,
                    onSave: { score, note in
                        closingOnSuccess(await viewModel.rate(title, score: score, note: note))
                    },
                    onClear: { closingOnSuccess(await viewModel.clearRating(title)) }
                )
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
            Text("Tap everything you've watched. Rating is optional, but a few ratings give your library a head start.")
                .font(DesignTypography.body)
                .foregroundStyle(DesignTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            goal
        }
        .padding(.top, DesignSpacing.sm)
    }

    /// The optional rating goal: a bar and count, then a checkmark once it is met.
    private var goal: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            HStack(spacing: DesignSpacing.sm) {
                if viewModel.isGoalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTheme.accent)
                }
                Text(viewModel.goalText)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textPrimary)
                Spacer(minLength: DesignSpacing.sm)
                Text("Goal: \(OnboardingSeenViewModel.ratingGoal) · optional")
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
            }
            ProgressView(value: viewModel.goalFraction)
                .tint(DesignTheme.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Optional rating goal")
        .accessibilityValue(viewModel.goalText)
        .accessibilityHint("Continue works at any time.")
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
                OnboardingRateChip(title: title.draft.title, score: viewModel.score(for: title)) {
                    rating = title
                }
            }
        }
    }

    /// The sheet leaves dismissal to its owner after a successful write.
    private func closingOnSuccess(_ result: AnnotationEditorWriteResult) -> AnnotationEditorWriteResult {
        if result == .succeeded {
            rating = nil
        }
        return result
    }

    private func retry() async {
        if viewModel.isSearching {
            await viewModel.search()
        } else {
            await viewModel.reload()
        }
    }
}
