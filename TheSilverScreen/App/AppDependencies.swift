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
        let listChanges = ListChangeNotice()
        let annotationsStoreURL = try FileAnnotationsStore.applicationSupportURL()
        let annotations = AnnotationsRepository(
            store: FileAnnotationsStore(fileURL: annotationsStoreURL),
            logger: logger
        )
        let imageLoader = ImageLoader(client: URLSessionHTTPClient.images(), logger: logger)
        let router = AppRouter()
        return AppDependencies(
            movies: movies,
            shows: shows,
            people: people,
            lists: lists,
            listsIndex: listsIndex,
            listChanges: listChanges,
            annotations: annotations,
            imageLoader: imageLoader,
            router: router,
            logger: logger
        )
    }
}
