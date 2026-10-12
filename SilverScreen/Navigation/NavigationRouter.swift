//
//  NavigationRouter.swift
//  SilverScreen
//

import Foundation

@Observable
@MainActor
final class NavigationRouter {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Synchronizes the path after a UIKit interactive pop (swipe-back).
    func pop(toDepth depth: Int) {
        let clamped = max(0, depth)
        guard path.count > clamped else { return }
        path = Array(path.prefix(clamped))
    }
}
