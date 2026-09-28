//
//  HTTPTransport.swift
//  TheSilverScreen
//
//  Shared status / URLError mapping and retry-with-backoff for JSON and images.
//

import Foundation

enum HTTPTransport {
    /// Delays between attempts 1→2 and 2→3. Three attempts total.
    static let retryDelays: [TimeInterval] = [0.5, 1.0]

    static func data(
        for request: URLRequest,
        client: any HTTPClient,
        logger: any AppLogging,
        context: String,
        sleeper: any Sleeper = TaskSleeper(),
        maxAttempts: Int = retryDelays.count + 1
    ) async throws -> Data {
        var lastError: AppError = .unknown

        for attempt in 0..<maxAttempts {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await client.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                logger.error(
                    "\(context) request failed: \(error.code.rawValue)",
                    category: .networking
                )
                lastError = mapURLError(error)
                if shouldAutomaticallyRetry(lastError), attempt < maxAttempts - 1 {
                    try await sleeper.sleep(seconds: retryDelays[attempt])
                    continue
                }
                throw lastError
            } catch {
                logger.error(
                    "\(context) request failed with unknown transport error",
                    category: .networking
                )
                throw AppError.unknown
            }

            do {
                try throwIfUnsuccessful(
                    status: response.statusCode,
                    logger: logger,
                    context: context
                )
                return data
            } catch let error as AppError {
                lastError = error
                if shouldAutomaticallyRetry(error), attempt < maxAttempts - 1 {
                    try await sleeper.sleep(seconds: retryDelays[attempt])
                    continue
                }
                throw error
            }
        }

        throw lastError
    }

    /// Automatic retries are narrower than UI `isRetryable`: timeouts, 5xx, and unknown transport
    /// errors only — never 4xx, and never `.offline`. A truly offline request will not succeed by
    /// retrying, and the session now fails fast (see `URLSessionHTTPClient.makeConfiguration`), so
    /// retrying it just delays the offline message. The UI still offers a manual retry for
    /// `.offline` via `AppError.isRetryable`.
    static func shouldAutomaticallyRetry(_ error: AppError) -> Bool {
        switch error {
        case .timedOut, .unknown:
            return true
        case .server(let status):
            return (500..<600).contains(status)
        case .offline, .unauthorized, .decoding, .persistence, .missingAPIKey:
            return false
        }
    }

    static func mapURLError(_ error: URLError) -> AppError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .unknown
        }
    }

    static func throwIfUnsuccessful(
        status: Int,
        logger: any AppLogging,
        context: String = "Request"
    ) throws {
        switch status {
        case 200..<300:
            return
        case 401, 403:
            logger.error("\(context) unauthorized status \(status)", category: .networking)
            throw AppError.unauthorized
        case 500..<600:
            logger.error("\(context) server status \(status)", category: .networking)
            throw AppError.server(status: status)
        default:
            logger.error("\(context) unexpected status \(status)", category: .networking)
            throw AppError.server(status: status)
        }
    }
}
