//
//  OnboardingGate.swift
//  SilverScreen
//
//  Decides whether the first-launch flow covers the tabs, and closes it. Built
//  once in `SceneDelegate`; the Library's empty state reopens it.
//

import SwiftUI

/// Presentation state for the onboarding full-screen cover.
@Observable
@MainActor
final class OnboardingGate {
    /// Bound to the full-screen cover over `RootTabView`.
    var isPresented = false
    /// True from the launch check's decision until its cover is on screen. The tabs
    /// stay hidden meanwhile, so Browse never shows under a cover on its way up.
    private(set) var isLaunchCoverPending = false

    private let marker: OnboardingMarkerStore
    private let lists: ListsRepository
    private let annotations: AnnotationsRepository
    private let isDemo: Bool
    private let router: AppRouter
    /// Counts finishes (not skips) as `Onboarding.finished`.
    private let analytics: any AnalyticsClient
    private let library: LibraryHomeViewModel?
    /// The feature tour that picks up on the Library after a finish (not a skip).
    private let tour: TourController?

    init(
        marker: OnboardingMarkerStore,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        isDemo: Bool,
        router: AppRouter,
        analytics: any AnalyticsClient,
        library: LibraryHomeViewModel? = nil,
        tour: TourController? = nil
    ) {
        self.marker = marker
        self.lists = lists
        self.annotations = annotations
        self.isDemo = isDemo
        self.router = router
        self.analytics = analytics
        self.library = library
        self.tour = tour
    }

    /// First launch means nothing saved anywhere and no earlier finish or skip.
    /// Marketing captures never see the flow.
    static func shouldPresent(
        snapshot: LibrarySnapshot,
        annotations: [MediaAnnotation],
        completedAt: Date?,
        isDemo: Bool
    ) -> Bool {
        guard !isDemo, completedAt == nil else { return false }
        guard snapshot.entries.isEmpty else { return false }
        return !annotations.contains { $0.score != nil }
    }

    /// True when launch has to read the library to decide: no finish or skip yet, and
    /// not a capture. Anyone who has finished or skipped once launches without waiting.
    var needsLaunchCheck: Bool {
        !isDemo && marker.completedAt() == nil
    }

    /// Runs `evaluate()` but returns after `limit` seconds even if the read is still
    /// going. Launch holds its first frame on this; a slow read then lets the tabs
    /// show and the cover follows when the read finishes.
    func evaluate(waitingAtMost limit: TimeInterval, sleeper: any Sleeper = TaskSleeper()) async {
        let check = Task { await evaluate() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await check.value }
            group.addTask { try? await sleeper.sleep(seconds: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Reads the library and ratings once at launch. An unreadable library is
    /// treated as not new, so a disk error never pushes someone into onboarding.
    func evaluate() async {
        guard !isDemo, marker.completedAt() == nil else { return }
        guard let snapshot = try? await lists.snapshot() else { return }
        let saved = await annotations.saved()
        guard Self.shouldPresent(
            snapshot: snapshot,
            annotations: saved,
            completedAt: marker.completedAt(),
            isDemo: isDemo
        ) else { return }
        isLaunchCoverPending = true
    }

    /// Puts the launch check's cover up without the slide, once the tabs exist. A
    /// cover bound to `true` before its first render always slides, so this waits
    /// for `RootTabView` to appear.
    func presentLaunchCover() {
        guard isLaunchCoverPending, !isPresented else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = true
        }
    }

    /// The launch cover is on screen, so the tabs can show under it.
    func launchCoverDidAppear() {
        isLaunchCoverPending = false
    }

    /// The Library's "Get started" button. Works after a skip or finish too.
    func reopen() {
        isPresented = true
    }

    /// Skip: write the marker and close where the user already was.
    func skip() {
        marker.markCompleted()
        isPresented = false
    }

    /// Finish: write the marker, land on the Library root with the new picks, and
    /// start the feature tour there.
    func finish() async {
        marker.markCompleted()
        analytics.send(.onboardingFinished)
        router.favorites.popToRoot()
        router.openLibrary()
        isPresented = false
        await library?.load()
        await tour?.start()
    }
}
