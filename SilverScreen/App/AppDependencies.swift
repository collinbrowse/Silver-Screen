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
    let diary: DiaryContext
    let awards: AwardsRepository
    let imageLoader: ImageLoader
    let libraryStore: SQLiteLibraryStore
    let router: AppRouter
    let logger: any AppLogging
    let settings: SettingsContext
    let reviewPrompter: ReviewPrompter
    /// Anonymous product events. Disabled without a TelemetryDeck app ID and for demo launches.
    let analytics: any AnalyticsClient
    /// Screen details for analytics, reported by `SceneDelegate`.
    let analyticsDevice: AnalyticsDeviceContext
    /// Starts analytics sessions on launch and on returning to the app.
    let analyticsSession: AnalyticsSessionTracker

    /// The awards download cache, or nil when Application Support is unavailable. The cache
    /// only holds newer catalog downloads, so losing it must not stop the app from starting.
    private static func awardsCacheURL(logger: any AppLogging) -> URL? {
        do {
            return try AwardsRepository.cacheURL()
        } catch {
            logger.error(
                "Awards cache unavailable: \(StartupFailureView.errorCode(error))",
                category: .persistence
            )
            return nil
        }
    }

    /// Builds the app's dependency graph. A demo launch swaps in a throwaway library.
    static func live(demo: DemoMode? = nil) throws -> AppDependencies {
        let logger = OSAppLogger()
        let connection = try TMDBConnection.fromBundle()
        let httpClient = URLSessionHTTPClient()
        let appInfo = AppInfo.live()
        let analyticsPreferences = AnalyticsPreferences()
        let analyticsDevice = AnalyticsDeviceContext()
        // Demo launches write a seeded library for screenshots; those writes are not real use.
        let analytics: any AnalyticsClient = demo == nil
            ? TelemetryDeckClient.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:],
                client: httpClient,
                preferences: analyticsPreferences,
                appInfo: appInfo,
                device: analyticsDevice,
                logger: logger
            )
            : DisabledAnalytics()
        let movies = MovieRepository(
            client: httpClient,
            connection: connection,
            logger: logger
        )
        let people = PersonRepository(
            client: httpClient,
            connection: connection,
            logger: logger
        )
        let shows = TVRepository(
            client: httpClient,
            connection: connection,
            logger: logger
        )
        let libraryStore = try demo?.libraryStore() ?? SQLiteLibraryStore.live()
        let listsIndex = ListsIndex()
        let lists = ListsRepository(
            store: LibraryListsStoreAdapter(library: libraryStore),
            logger: logger,
            index: listsIndex,
            analytics: analytics
        )
        let annotations = AnnotationsRepository(
            store: LibraryAnnotationsStoreAdapter(library: libraryStore),
            logger: logger,
            analytics: analytics
        )
        let diary = DiaryContext(
            diary: DiaryRepository(store: LibraryDiaryStoreAdapter(library: libraryStore), logger: logger),
            lists: lists,
            logger: logger,
            annotations: annotations
        )
        // The eye on a movie logs a diary watch, so the toast needs the diary.
        let listChanges = ListChangeNotice(annotations: annotations, diary: diary)
        let tvWatch = TVWatchRepository(
            store: LibraryTVWatchStoreAdapter(library: libraryStore),
            lists: lists,
            logger: logger
        )
        let imageLoader = ImageLoader(client: URLSessionHTTPClient.images(), logger: logger)
        let awards = AwardsRepository(
            client: httpClient,
            bundleURL: Bundle.main.url(forResource: "AwardsCatalog", withExtension: "json"),
            cacheURL: awardsCacheURL(logger: logger),
            logger: logger
        )
        let router = AppRouter()
        let reviewPrompter = ReviewPrompter(
            appVersion: appInfo.marketingVersion,
            defaults: .standard
        ) { cutoff in
            try await libraryStore.countRatings(createdAfter: cutoff)
        }
        let settings = SettingsContext(
            appInfo: appInfo,
            analyticsSharing: AnalyticsSharing(preferences: analyticsPreferences)
        ) { submission in
            SentryBootstrap.sendFeedback(message: submission.message, email: submission.email)
        }
        return AppDependencies(
            movies: movies,
            shows: shows,
            people: people,
            lists: lists,
            listsIndex: listsIndex,
            listChanges: listChanges,
            annotations: annotations,
            tvWatch: tvWatch,
            diary: diary,
            awards: awards,
            imageLoader: imageLoader,
            libraryStore: libraryStore,
            router: router,
            logger: logger,
            settings: settings,
            reviewPrompter: reviewPrompter,
            analytics: analytics,
            analyticsDevice: analyticsDevice,
            analyticsSession: AnalyticsSessionTracker(analytics: analytics)
        )
    }
}
