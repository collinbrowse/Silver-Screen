//
//  ImageLoader.swift
//  TheSilverScreen
//

import Foundation
import UIKit
import ImageIO

actor ImageLoader {
    /// A coalesced fetch shared by every caller for one URL.
    ///
    /// The fetch is an unstructured task so a second caller can await the same work. That task
    /// does not inherit a caller's cancellation, so each real caller is tracked by id and the
    /// shared task is cancelled only when the last real caller goes away.
    private struct InFlightEntry {
        let task: Task<UIImage, Error>
        /// Real (non-prefetch) callers still awaiting this task. Prefetch does not count, so
        /// cancelling a prefetch can never tear down a fetch a now-visible cell still needs.
        var realWaiterIDs: Set<UUID>
    }

    private let client: any HTTPClient
    private let logger: any AppLogging
    private let sleeper: any Sleeper
    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: InFlightEntry] = [:]

    init(
        client: any HTTPClient,
        logger: any AppLogging,
        sleeper: any Sleeper = TaskSleeper()
    ) {
        self.client = client
        self.logger = logger
        self.sleeper = sleeper
        memoryCache.countLimit = 200
    }

    func image(for url: URL, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        try await image(for: url, targetSize: targetSize, scale: scale, isPrefetch: false)
    }

    /// Shared fetch path. `isPrefetch` callers do not register as real waiters, which is what
    /// lets `cancelPrefetch` leave a coalesced fetch running for a visible cell.
    private func image(
        for url: URL,
        targetSize: CGSize,
        scale: CGFloat,
        isPrefetch: Bool
    ) async throws -> UIImage {
        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let waiterID = UUID()
        let task: Task<UIImage, Error>
        if let existing = inFlight[url] {
            task = existing.task
        } else {
            task = Task<UIImage, Error> {
                try await Self.fetchAndDecode(
                    url: url,
                    targetSize: targetSize,
                    scale: scale,
                    client: client,
                    logger: logger,
                    sleeper: sleeper
                )
            }
            inFlight[url] = InFlightEntry(task: task, realWaiterIDs: [])
        }

        if !isPrefetch {
            inFlight[url]?.realWaiterIDs.insert(waiterID)
        }

        do {
            let image = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.releaseWaiter(url: url, waiterID: isPrefetch ? nil : waiterID) }
            }
            memoryCache.setObject(image, forKey: cacheKey)
            inFlight[url] = nil
            try Task.checkCancellation()
            return image
        } catch {
            if !isPrefetch {
                releaseWaiter(url: url, waiterID: waiterID)
            }
            throw error
        }
    }

    /// Drops one real caller. Cancels the shared fetch once nobody visible still needs it.
    /// A second call for the same id is a no-op, so the cancellation handler and the `catch`
    /// can both run without tearing down a fetch another cell is still awaiting.
    private func releaseWaiter(url: URL, waiterID: UUID?) {
        guard var entry = inFlight[url] else { return }
        if let waiterID {
            guard entry.realWaiterIDs.remove(waiterID) != nil else { return }
            inFlight[url] = entry
        }
        guard entry.realWaiterIDs.isEmpty else { return }
        entry.task.cancel()
        inFlight[url] = nil
    }

    /// Visible callers sharing the fetch for `url`. Tests wait on this so a second caller has
    /// joined before the first is cancelled.
    func realWaiterCount(for url: URL) -> Int {
        inFlight[url]?.realWaiterIDs.count ?? 0
    }

    func prefetch(urls: [URL], targetSize: CGSize, scale: CGFloat) {
        for url in urls {
            Task { try? await image(for: url, targetSize: targetSize, scale: scale, isPrefetch: true) }
        }
    }

    func cancelPrefetch(urls: [URL]) {
        for url in urls {
            guard let entry = inFlight[url] else { continue }
            // A now-visible cell may be awaiting this same coalesced task. Only cancel a fetch
            // that no real caller depends on; otherwise leave it running.
            guard entry.realWaiterIDs.isEmpty else { continue }
            entry.task.cancel()
            inFlight[url] = nil
        }
    }

    // MARK: - TMDB size selection

    enum ImageKind: Sendable {
        case poster
        case backdrop
        case profile
    }

    static func posterURL(path: String, targetWidthPoints: CGFloat, scale: CGFloat) -> URL? {
        let pixels = targetWidthPoints * scale
        let sizeToken: String
        switch pixels {
        case ..<92: sizeToken = "w92"
        case ..<154: sizeToken = "w154"
        case ..<185: sizeToken = "w185"
        case ..<342: sizeToken = "w342"
        default: sizeToken = "w500"
        }
        let normalized = path.hasPrefix("/") ? path : "/" + path
        return URL(string: "https://image.tmdb.org/t/p/\(sizeToken)\(normalized)")
    }

    static func imageURL(
        path: String,
        kind: ImageKind,
        targetWidthPoints: CGFloat,
        scale: CGFloat
    ) -> URL? {
        if kind == .poster {
            // Carousel/fullscreen posters may request larger than list cells.
            let pixels = targetWidthPoints * scale
            let sizeToken: String
            switch pixels {
            case ..<92: sizeToken = "w92"
            case ..<154: sizeToken = "w154"
            case ..<185: sizeToken = "w185"
            case ..<342: sizeToken = "w342"
            case ..<500: sizeToken = "w500"
            default: sizeToken = "w780"
            }
            let normalized = path.hasPrefix("/") ? path : "/" + path
            return URL(string: "https://image.tmdb.org/t/p/\(sizeToken)\(normalized)")
        }
        let pixels = targetWidthPoints * scale
        let sizeToken = sizeToken(for: kind, pixels: pixels)
        let normalized = path.hasPrefix("/") ? path : "/" + path
        return URL(string: "https://image.tmdb.org/t/p/\(sizeToken)\(normalized)")
    }

    private static func sizeToken(for kind: ImageKind, pixels: CGFloat) -> String {
        switch kind {
        case .poster:
            return "w500"
        case .backdrop:
            switch pixels {
            case ..<300: return "w300"
            case ..<780: return "w780"
            default: return "w1280"
            }
        case .profile:
            switch pixels {
            case ..<45: return "w45"
            case ..<185: return "w185"
            default: return "h632"
            }
        }
    }

    // MARK: - Fetch + decode

    /// Fetches the bytes and downsamples them **off** the actor. Being `nonisolated async`, this
    /// runs on the generic executor, so the CPU-heavy `CGImageSource` decode no longer serializes
    /// on ImageLoader's actor — where it would block cache hits and coalescing for every other
    /// caller during a fast scroll.
    private nonisolated static func fetchAndDecode(
        url: URL,
        targetSize: CGSize,
        scale: CGFloat,
        client: any HTTPClient,
        logger: any AppLogging,
        sleeper: any Sleeper
    ) async throws -> UIImage {
        let request = URLRequest(url: url)
        let data = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: "Image",
            sleeper: sleeper
        )
        return try downsample(data: data, targetSize: targetSize, scale: scale)
    }

    // MARK: - Downsampling

    private static func downsample(data: Data, targetSize: CGSize, scale: CGFloat) throws -> UIImage {
        let maxPixelSize = max(targetSize.width, targetSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            throw AppError.decoding
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            downsampleOptions as CFDictionary
        ) else {
            throw AppError.decoding
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
