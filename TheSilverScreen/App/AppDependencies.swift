//
//  AppDependencies.swift
//  TheSilverScreen
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
        let listsStoreURL = try FileListsStore.applicationSupportURL()
        let listsIndex = ListsIndex()
        let lists = ListsRepository(
            store: FileListsStore(fileURL: listsStoreURL),
            logger: logger,
            index: listsIndex
        )
        let annotationsStoreURL = try FileAnnotationsStore.applicationSupportURL()
        let annotations = AnnotationsRepository(
            store: FileAnnotationsStore(fileURL: annotationsStoreURL),
            logger: logger
        )
        let listChanges = ListChangeNotice(annotations: annotations)
        let tvWatchStoreURL = try FileTVWatchStore.applicationSupportURL()
        let tvWatch = TVWatchRepository(
            store: FileTVWatchStore(fileURL: tvWatchStoreURL),
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
            router: router,
            logger: logger
        )
    }
}
