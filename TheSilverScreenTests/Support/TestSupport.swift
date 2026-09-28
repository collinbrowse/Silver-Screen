//
//  TestSupport.swift
//  TheSilverScreenTests
//

import Foundation
import UIKit
@testable import TheSilverScreen

/// Encoded PNG bytes for a solid square — valid input for the ImageLoader downsample path.
enum TestImages {
    static func pngData(size: CGFloat = 8) -> Data {
        let dimension = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: dimension)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: dimension))
        }
        return image.pngData()!
    }
}

extension AnnotationsRepository {
    static func empty() -> AnnotationsRepository {
        AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
    }
}

struct SilentLogger: AppLogging {
    func debug(_ message: String, category: LogCategory) {}
    func error(_ message: String, category: LogCategory) {}
}

extension MovieRepository {
    /// Test factory: real repository over a fake client, no retry backoff delay.
    static func test(
        client: any HTTPClient,
        apiKey: String = "test",
        logger: any AppLogging = SilentLogger()
    ) -> MovieRepository {
        MovieRepository(
            client: client,
            apiKey: apiKey,
            logger: logger,
            sleeper: NoopSleeper()
        )
    }
}

extension PersonRepository {
    /// Test factory: real repository over a fake client, no retry backoff delay.
    static func test(
        client: any HTTPClient,
        apiKey: String = "test",
        logger: any AppLogging = SilentLogger()
    ) -> PersonRepository {
        PersonRepository(
            client: client,
            apiKey: apiKey,
            logger: logger,
            sleeper: NoopSleeper()
        )
    }
}

extension TVRepository {
    /// Test factory: real repository over a fake client, no retry backoff delay.
    static func test(
        client: any HTTPClient,
        apiKey: String = "test",
        logger: any AppLogging = SilentLogger()
    ) -> TVRepository {
        TVRepository(
            client: client,
            apiKey: apiKey,
            logger: logger,
            sleeper: NoopSleeper()
        )
    }
}

extension ImageLoader {
    static func test(
        client: any HTTPClient,
        logger: any AppLogging = SilentLogger()
    ) -> ImageLoader {
        ImageLoader(client: client, logger: logger, sleeper: NoopSleeper())
    }
}

enum TestMovies {
    static func make(
        id: Int = 1,
        title: String = "Short Movie Title",
        posterPath: String? = nil,
        releaseDate: Date? = nil,
        voteAverage: Double = 8.0,
        genreIDs: [Int] = [],
        popularity: Double = 0
    ) -> Movie {
        Movie(
            id: id,
            title: title,
            posterPath: posterPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genreIDs: genreIDs,
            popularity: popularity
        )
    }

    static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }
}
