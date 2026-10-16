//
//  OnboardingGate.swift
//  SilverScreen
//
//  Decides whether the first-launch flow covers the tabs, and closes it. Built
//  once in `SceneDelegate`; the Library's empty state reopens it.
//

import Foundation

/// Presentation state for the onboarding full-screen cover.
@Observable
@MainActor
final class OnboardingGate {
    /// Bound to the full-screen cover over `RootTabView`.
    var isPresented = false

    private let marker: OnboardingMarkerStore
    private let lists: ListsRepository
    private let annotations: AnnotationsRepository
    private let isDemo: Bool
    private let router: AppRouter
    private let library: LibraryHomeViewModel?

    init(
        marker: OnboardingMarkerStore,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        isDemo: Bool,
        router: AppRouter,
        library: LibraryHomeViewModel? = nil
    ) {
        self.marker = marker
        self.lists = lists
        self.annotations = annotations
        self.isDemo = isDemo
        self.router = router
        self.library = library
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

    /// Reads the library and ratings once at launch. An unreadable library is
    /// treated as not new, so a disk error never pushes someone into onboarding.
    func evaluate() async {
        guard !isDemo, marker.completedAt() == nil else { return }
        guard let snapshot = try? await lists.snapshot() else { return }
        let saved = await annotations.saved()
        isPresented = Self.shouldPresent(
            snapshot: snapshot,
            annotations: saved,
            completedAt: marker.completedAt(),
            isDemo: isDemo
        )
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

    /// Finish: write the marker and land on the Library root with the new picks.
    func finish() async {
        marker.markCompleted()
        router.favorites.popToRoot()
        router.openLibrary()
        isPresented = false
        await library?.load()
    }
}
