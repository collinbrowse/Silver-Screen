//
//  ImageLoaderTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class ImageLoaderTests: XCTestCase {

    func test_posterURL_selectsW342_for128ptAt2x() {
        let url = ImageLoader.posterURL(path: "/poster.jpg", targetWidthPoints: 128, scale: 2)

        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w342/poster.jpg")
    }

    func test_posterURL_selectsW92_forNarrowTarget() {
        let url = ImageLoader.posterURL(path: "poster.jpg", targetWidthPoints: 40, scale: 2)

        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w92/poster.jpg")
    }

    func test_posterURL_selectsW500_forLargeTarget() {
        let url = ImageLoader.posterURL(path: "/poster.jpg", targetWidthPoints: 200, scale: 3)

        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    func test_image_whenOffline_throwsOffline() async {
        let loader = ImageLoader.test(
            client: FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
        )
        let url = URL(string: "https://image.tmdb.org/t/p/w92/poster.jpg")!

        do {
            _ = try await loader.image(for: url, targetSize: CGSize(width: 40, height: 60), scale: 2)
            XCTFail("Expected offline error")
        } catch let error as AppError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_image_whenTimedOut_throwsTimedOut() async {
        let loader = ImageLoader.test(
            client: FakeHTTPClient(result: .failure(URLError(.timedOut)))
        )
        let url = URL(string: "https://image.tmdb.org/t/p/w92/poster.jpg")!

        do {
            _ = try await loader.image(for: url, targetSize: CGSize(width: 40, height: 60), scale: 2)
            XCTFail("Expected timedOut error")
        } catch let error as AppError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_image_decodesResponseToImage() async throws {
        let loader = ImageLoader.test(client: FakeHTTPClient(stub: .success(TestImages.pngData())))
        let url = URL(string: "https://image.tmdb.org/t/p/w92/poster.jpg")!

        let image = try await loader.image(for: url, targetSize: CGSize(width: 8, height: 8), scale: 1)

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func test_cancelPrefetch_whileRealRequestInFlight_doesNotCancelIt() async throws {
        let client = BlockingHTTPClient(responseData: TestImages.pngData())
        let loader = ImageLoader.test(client: client)
        let url = URL(string: "https://image.tmdb.org/t/p/w92/poster.jpg")!

        // A visible cell's fetch, held open at the network boundary.
        let realFetch = Task {
            try await loader.image(for: url, targetSize: CGSize(width: 8, height: 8), scale: 1)
        }
        await client.waitUntilEntered()

        // Scrolling reverses; the prefetcher cancels this URL. It must not kill the cell's fetch.
        await loader.cancelPrefetch(urls: [url])
        await client.release()

        let image = try await realFetch.value
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func test_cancellingTheOnlyRealCaller_cancelsTheFetch() async {
        let client = BlockingHTTPClient(responseData: TestImages.pngData())
        let loader = ImageLoader.test(client: client)
        let url = URL(string: "https://image.tmdb.org/t/p/w92/poster.jpg")!

        let fetch = Task {
            try await loader.image(for: url, targetSize: CGSize(width: 8, height: 8), scale: 1)
        }
        await client.waitUntilEntered()
        fetch.cancel()

        do {
            _ = try await fetch.value
            XCTFail("Expected the cancelled fetch to throw")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func test_cancellingOneOfTwoRealCallers_keepsTheSharedFetch() async throws {
        let client = BlockingHTTPClient(responseData: TestImages.pngData())
        let loader = ImageLoader.test(client: client)
        let url = URL(string: "https://image.tmdb.org/t/p/w92/poster.jpg")!

        let first = Task {
            try await loader.image(for: url, targetSize: CGSize(width: 8, height: 8), scale: 1)
        }
        await client.waitUntilEntered()

        let second = Task {
            try await loader.image(for: url, targetSize: CGSize(width: 8, height: 8), scale: 1)
        }
        for _ in 0..<50 {
            if await loader.realWaiterCount(for: url) >= 2 { break }
            await Task.yield()
        }
        let joined = await loader.realWaiterCount(for: url)
        XCTAssertGreaterThanOrEqual(joined, 2)

        first.cancel()
        for _ in 0..<50 {
            if await loader.realWaiterCount(for: url) <= 1 { break }
            await Task.yield()
        }

        await client.release()
        let image = try await second.value
        XCTAssertGreaterThan(image.size.width, 0)

        do {
            _ = try await first.value
            XCTFail("Expected the cancelled caller to throw")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        let requests = await client.requestCount
        XCTAssertEqual(requests, 1)
    }
}
