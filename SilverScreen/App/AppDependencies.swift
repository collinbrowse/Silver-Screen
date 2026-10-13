//
//  AppDependencies.swift
//  SilverScreen
//

import Foundation

@MainActor
struct AppDependencies {
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let listChanges: ListChangeNotice
    let annotations: AnnotationsRepository
    let tvWatch: TVWatchRepository
    let awards: AwardsRepository
    let imageLoader: ImageLoader
    let libraryStore: SQLiteLibraryStore
    let router: AppRouter
    let logger: any AppLogging

    static func live() throws -> AppDependencies {
        let logger = OSAppLogger()
        let apiKey = try TMDBAPIKey.fromBundle()
        let httpClient = URLSessionHTTPClient()
        let movies = MovieRepository(
            client: httpClient,
            apiKey: apiKey,
            logger: logger
        )
        let people = PersonRepository(
            client: httpClient,
            apiKey: apiKey,
            logger: logger
        )
        let shows = TVRepository(
            client: httpClient,
            apiKey: apiKey,
            logger: logger
        )
        let libraryStore = try SQLiteLibraryStore.live()
        let listsIndex = ListsIndex()
        let lists = ListsRepository(
            store: LibraryListsStoreAdapter(library: libraryStore),
            logger: logger,
            index: listsIndex
        )
        let annotations = AnnotationsRepository(
            store: LibraryAnnotationsStoreAdapter(library: libraryStore),
            logger: logger
        )
        let listChanges = ListChangeNotice(annotations: annotations)
        let tvWatch = TVWatchRepository(
            store: LibraryTVWatchStoreAdapter(library: libraryStore),
            lists: lists,
            logger: logger
        )
        let imageLoader = ImageLoader(client: URLSessionHTTPClient.images(), logger: logger)
        let awards = AwardsRepository(
            client: httpClient,
            bundleURL: Bundle.main.url(forResource: "AwardsCatalog", withExtension: "json"),
            cacheURL: try AwardsRepository.cacheURL(),
            logger: logger
        )
        let router = AppRouter()
        return AppDependencies(
            movies: movies,
            shows: shows,
            people: people,
            lists: lists,
            listsIndex: listsIndex,
            listChanges: listChanges,
            annotations: annotations,
            tvWatch: tvWatch,
            awards: awards,
            imageLoader: imageLoader,
            libraryStore: libraryStore,
            router: router,
            logger: logger
        )
    }
}
