//
//  OnboardingViewModel.swift
//  SilverScreen
//
//  The first-launch flow: welcome, what you have seen, what you want to watch.
//  Skip and finish both close through `OnboardingGate`, which writes the marker.
//

import Foundation

/// The screens of the onboarding flow, in order.
enum OnboardingStep: Int, Sendable, Equatable, CaseIterable {
    case welcome
    case seen
    case watchlist
}

/// Owns the current step and the two grid view models.
@Observable
@MainActor
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .welcome
    let seen: OnboardingSeenViewModel
    let watchlist: OnboardingWatchlistViewModel

    private let gate: OnboardingGate

    init(
        movies: MovieRepository,
        shows: TVRepository,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository,
        awards: AwardsRepository,
        gate: OnboardingGate
    ) {
        self.seen = OnboardingSeenViewModel(
            movies: movies,
            shows: shows,
            lists: lists,
            annotations: annotations,
            tvWatch: tvWatch,
            awards: awards
        )
        self.watchlist = OnboardingWatchlistViewModel(movies: movies, shows: shows, lists: lists)
        self.gate = gate
    }

    func getStarted() {
        step = .seen
    }

    /// Moves to the watchlist grid at any rating count.
    func continueToWatchlist() {
        step = .watchlist
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Picks already saved stay saved; skipping only stops the flow.
    func skip() {
        gate.skip()
    }

    func finish() async {
        await gate.finish()
    }
}
