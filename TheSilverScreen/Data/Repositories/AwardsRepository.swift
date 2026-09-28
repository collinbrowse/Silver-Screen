//
//  AwardsRepository.swift
//  TheSilverScreen
//
//  Loads the bundled awards catalog, and at most once a week replaces it with
//  the newer copy published on main. Lookup stays in memory after that.
//

import Foundation

/// In-memory award lookup. The weekly file download is the only network call.
actor AwardsRepository {
    static let remoteCatalogURL = URL(
        string: "https://raw.githubusercontent.com/collinbrowse/The-Silver-Screen/main/TheSilverScreen/Data/Resources/AwardsCatalog.json"
    )!
    static let pageSize = 20
    /// Fewer resolved credits than this is a stub, not a history worth listing.
    static let minimumListedCredits = 8
    private static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    private let client: (any HTTPClient)?
    private let bundleURL: URL?
    private let cacheURL: URL?
    private let stampURL: URL?
    private let remoteURL: URL?
    private let logger: (any AppLogging)?
    private let now: @Sendable () -> Date

    private var catalog: AwardsCatalog
    private var didLoadLocal = false
    private var localWaiters: [CheckedContinuation<Void, Never>] = []
    private var isLoadingLocal = false
    private var didDownload = false
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []
    private var isDownloading = false

    /// Test and preview catalog. Skips disk and the weekly download.
    init(catalog: AwardsCatalog) {
        self.catalog = catalog
        self.client = nil
        self.bundleURL = nil
        self.cacheURL = nil
        self.stampURL = nil
        self.remoteURL = nil
        self.logger = nil
        self.now = { Date() }
        self.didLoadLocal = true
        self.didDownload = true
    }

    init(
        client: any HTTPClient,
        bundleURL: URL?,
        cacheURL: URL,
        remoteURL: URL = AwardsRepository.remoteCatalogURL,
        logger: any AppLogging,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.catalog = .empty
        self.client = client
        self.bundleURL = bundleURL
        self.cacheURL = cacheURL
        self.stampURL = cacheURL
            .deletingLastPathComponent()
            .appendingPathComponent("AwardsCatalog.stamp.json")
        self.remoteURL = remoteURL
        self.logger = logger
        self.now = now
    }

    static func cacheURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("TheSilverScreen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("AwardsCatalog.json")
    }

    /// Reads the bundle and any newer cache. Safe to call from every screen.
    func ensureLoaded() async {
        if didLoadLocal { return }
        if isLoadingLocal {
            await withCheckedContinuation { localWaiters.append($0) }
            return
        }
        isLoadingLocal = true
        catalog = loadLocalCatalog()
        didLoadLocal = true
        isLoadingLocal = false
        let waiters = localWaiters
        localWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// Local load, then at most one download attempt per week.
    func prepare() async {
        await ensureLoaded()
        if didDownload { return }
        if isDownloading {
            await withCheckedContinuation { downloadWaiters.append($0) }
            return
        }
        isDownloading = true
        await downloadIfStale()
        didDownload = true
        isDownloading = false
        let waiters = downloadWaiters
        downloadWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func categories(in family: AwardFamily) async -> [AwardCategory] {
        await ensureLoaded()
        var counts: [String: Int] = [:]
        for credit in catalog.credits {
            guard credit.family == family, credit.work?.route(fallbackSeriesName: credit.title) != nil else {
                continue
            }
            counts[credit.category, default: 0] += 1
        }
        return counts
            .filter { $0.value >= Self.minimumListedCredits }
            .keys
            .sorted()
            .map { AwardCategory(name: $0) }
    }

    /// Ceremony year, newest first. Only credits that can open a detail screen.
    func creditPage(request: AwardTitleRequest, winners: Bool, page: Int) async -> AwardCreditPage {
        await ensureLoaded()
        let filtered = catalog.credits.filter { credit in
            guard credit.work?.route(fallbackSeriesName: credit.title) != nil else { return false }
            if let family = request.family, credit.family != family { return false }
            if let category = request.category, credit.category != category { return false }
            return credit.won == winners
        }
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.key < rhs.key
        }
        guard page >= 1 else {
            return AwardCreditPage(credits: [], page: page, hasMore: !sorted.isEmpty)
        }
        let start = (page - 1) * Self.pageSize
        guard start < sorted.count else {
            return AwardCreditPage(credits: [], page: page, hasMore: false)
        }
        let end = min(start + Self.pageSize, sorted.count)
        return AwardCreditPage(
            credits: Array(sorted[start..<end]),
            page: page,
            hasMore: end < sorted.count
        )
    }

    /// Prizes that name this person, with the title they were for.
    /// A missing IMDb id returns nothing.
    func personAwards(imdbID: String?) async -> [PersonAward] {
        await ensureLoaded()
        guard let imdbID else { return [] }
        return PersonAwardList.awards(from: catalog.credits, imdbID: imdbID)
    }

    func pillLabels(movieID: Int) async -> [AwardPill] {
        await labels { $0.work?.matches(movieID: movieID) == true }
    }

    func pillLabels(seriesID: Int) async -> [AwardPill] {
        await labels { $0.work?.matches(seriesID: seriesID) == true }
    }

    func pillLabels(seriesID: Int, seasonNumber: Int) async -> [AwardPill] {
        await labels { $0.work?.matches(seriesID: seriesID, seasonNumber: seasonNumber) == true }
    }

    func pillLabels(seriesID: Int, seasonNumber: Int, episodeNumber: Int) async -> [AwardPill] {
        await labels {
            $0.work?.matches(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            ) == true
        }
    }

    /// Newer cache wins. A missing side leaves the other. Used by tests and by `prepare`.
    static func preferred(bundle: AwardsCatalog?, cache: AwardsCatalog?) -> AwardsCatalog? {
        switch (bundle, cache) {
        case let (bundle?, cache?):
            return cache.generatedAt > bundle.generatedAt ? cache : bundle
        case let (bundle?, nil):
            return bundle
        case let (nil, cache?):
            return cache
        case (nil, nil):
            return nil
        }
    }

    private func labels(matching predicate: (AwardCredit) -> Bool) async -> [AwardPill] {
        await ensureLoaded()
        return AwardPillCopy.labels(from: catalog.credits.filter(predicate))
    }

    private func loadLocalCatalog() -> AwardsCatalog {
        let bundle = readCatalog(at: bundleURL, label: "bundle")
        let cache = readCatalog(at: cacheURL, label: "cache")
        let chosen = Self.preferred(bundle: bundle, cache: cache) ?? .empty
        logger?.debug(
            "Awards catalog loaded \(chosen.credits.count) credits",
            category: .persistence
        )
        return chosen
    }

    private func readCatalog(at url: URL?, label: String) -> AwardsCatalog? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try AwardsCatalog.decode(from: data)
        } catch {
            logger?.error("Awards catalog \(label) could not be read", category: .persistence)
            return nil
        }
    }

    private func downloadIfStale() async {
        guard let client, let remoteURL, let cacheURL else { return }
        let attempt = readStamp()
        if let attempt, now().timeIntervalSince(attempt) < Self.refreshInterval {
            return
        }
        writeStamp(now())
        do {
            var request = URLRequest(url: remoteURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await client.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                logger?.error(
                    "Awards catalog download failed: \(response.statusCode)",
                    category: .networking
                )
                return
            }
            let remote = try AwardsCatalog.decode(from: data)
            guard remote.generatedAt > catalog.generatedAt else { return }
            try data.write(to: cacheURL, options: .atomic)
            catalog = remote
            logger?.debug(
                "Awards catalog updated to \(remote.credits.count) credits",
                category: .networking
            )
        } catch is CancellationError {
            return
        } catch {
            logger?.error("Awards catalog download failed", category: .networking)
        }
    }

    private struct Stamp: Codable {
        var lastAttempt: Date
    }

    private func readStamp() -> Date? {
        guard let stampURL, FileManager.default.fileExists(atPath: stampURL.path) else { return nil }
        guard let data = try? Data(contentsOf: stampURL) else { return nil }
        return try? AwardJSON.decoder().decode(Stamp.self, from: data).lastAttempt
    }

    private func writeStamp(_ date: Date) {
        guard let stampURL else { return }
        guard let data = try? AwardJSON.encoder().encode(Stamp(lastAttempt: date)) else { return }
        try? data.write(to: stampURL, options: .atomic)
    }
}

