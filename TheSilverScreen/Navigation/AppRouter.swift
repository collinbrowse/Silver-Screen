//
//  AppRouter.swift
//  TheSilverScreen
//

import Foundation

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .browse
    let browse: NavigationRouter
    /// Library tab stack. The persisted key stays `favoritesPath` so a saved path still restores.
    let favorites: NavigationRouter
    let search: NavigationRouter

    init(
        selectedTab: AppTab = .browse,
        browse: NavigationRouter = NavigationRouter(),
        favorites: NavigationRouter = NavigationRouter(),
        search: NavigationRouter = NavigationRouter()
    ) {
        self.selectedTab = selectedTab
        self.browse = browse
        self.favorites = favorites
        self.search = search
    }

    func openLibrary() {
        selectedTab = .library
    }

    /// Serializable navigation state for scene restoration.
    var snapshot: RouterSnapshot {
        RouterSnapshot(
            selectedTab: selectedTab,
            browsePath: browse.path,
            favoritesPath: favorites.path,
            searchPath: search.path
        )
    }

    /// Restores a previously persisted navigation state. Call before the view tree is built so
    /// the restored path is present at first render.
    func restore(_ snapshot: RouterSnapshot) {
        selectedTab = snapshot.selectedTab
        browse.path = snapshot.browsePath
        favorites.path = snapshot.favoritesPath
        search.path = snapshot.searchPath
    }
}

/// Serializable snapshot of the selected tab and each tab's navigation path.
/// A snapshot written by the old Now Playing / Top Movies tabs still decodes:
/// missing paths come back empty, which returns that tab to its root.
struct RouterSnapshot: Codable, Equatable, Sendable {
    var selectedTab: AppTab
    var browsePath: [Route]
    var favoritesPath: [Route]
    var searchPath: [Route]

    private enum CodingKeys: String, CodingKey {
        case selectedTab
        case browsePath
        case favoritesPath
        case searchPath
    }

    init(
        selectedTab: AppTab,
        browsePath: [Route] = [],
        favoritesPath: [Route] = [],
        searchPath: [Route] = []
    ) {
        self.selectedTab = selectedTab
        self.browsePath = browsePath
        self.favoritesPath = favoritesPath
        self.searchPath = searchPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedTab = try container.decodeIfPresent(AppTab.self, forKey: .selectedTab) ?? .browse
        browsePath = try container.decodeIfPresent([Route].self, forKey: .browsePath) ?? []
        favoritesPath = try container.decodeIfPresent([Route].self, forKey: .favoritesPath) ?? []
        searchPath = try container.decodeIfPresent([Route].self, forKey: .searchPath) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedTab, forKey: .selectedTab)
        try container.encode(browsePath, forKey: .browsePath)
        try container.encode(favoritesPath, forKey: .favoritesPath)
        try container.encode(searchPath, forKey: .searchPath)
    }
}

/// Persists `RouterSnapshot` across launches so a jetsam kill returns the user to where they
/// were (selected tab and pushed detail screens) instead of the root.
struct RouterStateStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "com.collinbrowse.thesilverscreen.router.snapshot") {
        self.defaults = defaults
        self.key = key
    }

    func save(_ snapshot: RouterSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> RouterSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RouterSnapshot.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
