//
//  SceneDelegate.swift
//  TheSilverScreen
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private let routerStateStore = RouterStateStore()
    /// Held so navigation state can be persisted when the scene backgrounds.
    private var appRouter: AppRouter?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)

        do {
            let dependencies = try AppDependencies.live()
            // Restore the selected tab and pushed screens before the view tree is built.
            if let snapshot = routerStateStore.load() {
                dependencies.router.restore(snapshot)
            }
            appRouter = dependencies.router
            let libraryHomeViewModel = LibraryHomeViewModel(lists: dependencies.lists)
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
                libraryHomeViewModel: libraryHomeViewModel
            )
            window.rootViewController = UIHostingController(rootView: root)
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

    func sceneDidEnterBackground(_ scene: UIScene) {
        guard let appRouter else { return }
        routerStateStore.save(appRouter.snapshot)
    }
}
