//
//  SceneDelegate.swift
//  SilverScreen
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private let routerStateStore = RouterStateStore()
    /// Held so navigation state can be persisted when the scene backgrounds.
    private var appRouter: AppRouter?
    /// Held so foreground and background transitions reach analytics.
    private var analyticsSession: AnalyticsSessionTracker?
    private var analyticsDevice: AnalyticsDeviceContext?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)

        do {
            let demo = DemoMode.current()
            let dependencies = try AppDependencies.live(demo: demo)
            analyticsSession = dependencies.analyticsSession
            analyticsDevice = dependencies.analyticsDevice
            // Restore the selected tab and pushed screens before the view tree is built.
            // A demo launch opens where the capture asks and never saves its navigation.
            if let demo {
                if let snapshot = demo.routerSnapshot {
                    dependencies.router.restore(snapshot)
                }
            } else {
                if let snapshot = routerStateStore.load() {
                    dependencies.router.restore(snapshot)
                }
                appRouter = dependencies.router
            }
            let libraryHomeViewModel = LibraryHomeViewModel(lists: dependencies.lists)
            let tour = TourController(router: dependencies.router, lists: dependencies.lists)
            let onboarding = OnboardingGate(
                marker: OnboardingMarkerStore(defaults: .standard),
                lists: dependencies.lists,
                annotations: dependencies.annotations,
                isDemo: demo != nil,
                router: dependencies.router,
                analytics: dependencies.analytics,
                library: libraryHomeViewModel,
                tour: tour
            )
            Task { try? await dependencies.libraryStore.bootstrap() }
            Task { try? await dependencies.lists.loadIndex() }
            Task { await dependencies.awards.prepare() }
            Task {
                await WatchedRatings.sync(
                    annotations: dependencies.annotations,
                    lists: dependencies.lists,
                    movies: dependencies.movies,
                    logger: dependencies.logger
                )
            }
            // Silent cold-launch catalog check. Must not delay first frame.
            Task {
                await TVWatchReconcile.refreshWatchedCatalogs(
                    tvWatch: dependencies.tvWatch,
                    shows: dependencies.shows,
                    lists: dependencies.lists,
                    listChanges: dependencies.listChanges,
                    logger: dependencies.logger
                )
            }
            let root = RootTabView(
                router: dependencies.router,
                movies: dependencies.movies,
                shows: dependencies.shows,
                people: dependencies.people,
                lists: dependencies.lists,
                listsIndex: dependencies.listsIndex,
                listChanges: dependencies.listChanges,
                annotations: dependencies.annotations,
                tvWatch: dependencies.tvWatch,
                awards: dependencies.awards,
                imageLoader: dependencies.imageLoader,
                libraryHomeViewModel: libraryHomeViewModel,
                settings: dependencies.settings,
                onboarding: onboarding,
                tour: tour,
                reviewPrompter: dependencies.reviewPrompter
            )
            .environment(dependencies.diary)
            if let seedURL = demo?.seedURL {
                // A demo launch holds the first frame until the seed is written, so
                // screens never read an empty library and miss the seeded rows.
                let placeholder = UIViewController()
                placeholder.view.backgroundColor = .systemBackground
                window.rootViewController = placeholder
                Task { @MainActor in
                    await Self.seedDemoLibrary(from: seedURL, dependencies: dependencies)
                    try? await dependencies.lists.loadIndex()
                    if let library = try? await dependencies.lists.snapshot(),
                       let route = demo?.startingRoute(in: library) {
                        dependencies.router.restore(route)
                    }
                    window.rootViewController = UIHostingController(rootView: root)
                }
            } else if onboarding.needsLaunchCheck {
                // No finish or skip yet: hold the first frame until the library read
                // decides onboarding, so the cover is up from the first frame instead
                // of sliding over Browse. Capped so a slow read never stalls launch.
                let placeholder = UIViewController()
                placeholder.view.backgroundColor = .systemBackground
                window.rootViewController = placeholder
                Task { @MainActor in
                    await onboarding.evaluate(waitingAtMost: Self.onboardingCheckLimit)
                    window.rootViewController = UIHostingController(rootView: root)
                }
            } else {
                window.rootViewController = UIHostingController(rootView: root)
            }
        } catch {
            let message: String
            if let appError = error as? AppError {
                message = "\(appError.title)\n\n\(appError.message)"
            } else {
                message = "The app could not start."
            }
            window.rootViewController = UIHostingController(
                rootView: StartupFailureView(message: message)
            )
        }

        self.window = window
        window.makeKeyAndVisible()
    }

    /// Longest a first launch holds its first frame for the onboarding check.
    private static let onboardingCheckLimit: TimeInterval = 0.5

    /// Fills a demo launch's empty library through the real repositories.
    @MainActor
    private static func seedDemoLibrary(from url: URL, dependencies: AppDependencies) async {
        do {
            let seed = try DemoLibrarySeed.load(from: url)
            try await seed.apply(lists: dependencies.lists, annotations: dependencies.annotations)
            try await dependencies.libraryStore.backfillDiaryFromWatchedNow()
        } catch {
            dependencies.logger.error("Demo library seed failed: \(error)", category: .persistence)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called at launch too. Report the screen first so the session signal carries it.
        if let windowScene = scene as? UIWindowScene {
            reportDisplay(of: windowScene)
        }
        analyticsSession?.sceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        analyticsSession?.sceneDidEnterBackground()
        guard let appRouter else { return }
        routerStateStore.save(appRouter.snapshot)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry
    ) {
        reportDisplay(of: windowScene)
    }

    /// Orientation and screen size for analytics. Read here because UIKit stays in the delegates.
    private func reportDisplay(of windowScene: UIWindowScene) {
        let interfaceOrientation = windowScene.effectiveGeometry.interfaceOrientation
        let orientation: AnalyticsDisplay.Orientation = interfaceOrientation.isPortrait
            ? .portrait
            : interfaceOrientation.isLandscape ? .landscape : .unknown
        let bounds = windowScene.screen.bounds
        analyticsDevice?.update(
            AnalyticsDisplay(
                orientation: orientation,
                screenWidth: Int(bounds.width.rounded()),
                screenHeight: Int(bounds.height.rounded())
            )
        )
    }
}
