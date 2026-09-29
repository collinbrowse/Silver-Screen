//
//  FakeHTTPClient.swift
//  TheSilverScreenTests
//
//  The test seam for networking. Build real repositories over this — never
//  invent a MovieRepositoryProtocol. See .cursor/rules/testing.mdc.
//

import Foundation
@testable import TheSilverScreen

struct FakeHTTPClient: HTTPClient, Sendable {
    enum Stub: Sendable {
        case success(Data, status: Int = 200)
        case failure(Error)
    }

    private let stub: Stub

    init(stub: Stub) {
        self.stub = stub
    }

    init(result: Result<Data, Error>, status: Int = 200) {
        switch result {
            case .success(let data):
                self.stub = .success(data, status: status)
            case .failure(let error):
                self.stub = .failure(error)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch stub {
            case .success(let data, let status):
                let url = request.url ?? URL(string: "https://example.invalid")!
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (data, response)
            case .failure(let error):
                throw error
        }
    }
}

/// Records requests while returning a fixed stub — use for endpoint assertions.
actor RecordingHTTPClient: HTTPClient {
    private let stub: FakeHTTPClient.Stub
    private(set) var requests: [URLRequest] = []

    init(stub: FakeHTTPClient.Stub) {
        self.stub = stub
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await FakeHTTPClient(stub: stub).data(for: request)
    }

    var lastURL: URL? {
        requests.last?.url
    }

    var lastPath: String? {
        lastURL?.path
    }

    var lastAuthorizationHeader: String? {
        requests.last?.value(forHTTPHeaderField: "Authorization")
    }

    var requestCount: Int {
        requests.count
    }
}

/// Returns stubs in order — use to assert retry / eventual success.
actor SequencingHTTPClient: HTTPClient {
    private var stubs: [FakeHTTPClient.Stub]
    private(set) var requestCount = 0

    init(stubs: [FakeHTTPClient.Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        guard !stubs.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let stub = stubs.removeFirst()
        return try await FakeHTTPClient(stub: stub).data(for: request)
    }
}

/// Suspends inside `data(for:)` until `release()` is called, exposing `waitUntilEntered()`
/// so a test can act while a request is provably in flight — used to exercise coalescing and
/// prefetch-cancellation timing without sleeps.
actor BlockingHTTPClient: HTTPClient {
    private let responseData: Data
    private let status: Int
    private var hasEntered = false
    private var isReleased = false
    private var didResumeGate = false
    private var cancelRequested = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Error>?
    private(set) var requestCount = 0

    init(responseData: Data, status: Int = 200) {
        self.responseData = responseData
        self.status = status
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1

        try await withTaskCancellationHandler {
            if !isReleased {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if isReleased || didResumeGate {
                        continuation.resume()
                        markEntered()
                        return
                    }
                    if cancelRequested {
                        continuation.resume(throwing: CancellationError())
                        markEntered()
                        return
                    }
                    releaseContinuation = continuation
                    markEntered()
                }
            }
        } onCancel: {
            Task { await self.cancelWait() }
        }

        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
        return (responseData, response)
    }

    /// Returns once `data(for:)` has started, i.e. the request is registered and awaiting release.
    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        isReleased = true
        resumeGate { $0.resume() }
    }

    /// Unblocks a request whose task was cancelled. `withCheckedContinuation` would otherwise
    /// ignore cancellation and hang the test.
    private func cancelWait() {
        cancelRequested = true
        resumeGate { $0.resume(throwing: CancellationError()) }
    }

    private func markEntered() {
        guard !hasEntered else { return }
        hasEntered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
    }

    private func resumeGate(_ resume: (CheckedContinuation<Void, Error>) -> Void) {
        guard !didResumeGate, let releaseContinuation else { return }
        didResumeGate = true
        self.releaseContinuation = nil
        resume(releaseContinuation)
    }
}

/// Routes stubs by URL path fragment, or by an exact `name=value` query key when the path does not contain the key.
actor RoutingHTTPClient: HTTPClient {
    private var routes: [String: FakeHTTPClient.Stub]
    private let fallback: FakeHTTPClient.Stub
    private(set) var requests: [URLRequest] = []

    init(routes: [String: FakeHTTPClient.Stub], fallback: FakeHTTPClient.Stub = .failure(URLError(.badURL))) {
        self.routes = routes
        self.fallback = fallback
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let items = URLComponents(url: request.url ?? URL(string: "https://example.invalid")!, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        let match = routes
            .compactMap { key, stub -> (key: String, stub: FakeHTTPClient.Stub, score: Int)? in
                if let range = path.range(of: key) {
                    // Prefer matches that end later in the path, then longer keys.
                    let end = path.distance(from: path.startIndex, to: range.upperBound)
                    return (key, stub, end * 1_000 + key.count)
                }
                let exactQuery = items.contains { "\($0.name)=\($0.value ?? "")" == key }
                guard exactQuery else { return nil }
                return (key, stub, key.count)
            }
            .max(by: { $0.score < $1.score })
        let stub = match?.stub ?? fallback
        return try await FakeHTTPClient(stub: stub).data(for: request)
    }

    var requestCount: Int { requests.count }
}
