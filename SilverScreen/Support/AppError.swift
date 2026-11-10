//
//  AppError.swift
//  SilverScreen
//

import Foundation

enum AppError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case unauthorized
    case server(status: Int)
    case decoding
    case persistence
    case missingAccessToken
    case invalidBaseURL
    case unknown

    /// Localized headline for the error. The developer setup errors (`missingAccessToken`,
    /// `invalidBaseURL`) stay in English because only a misconfigured build shows them.
    var title: String {
        switch self {
            case .offline:
                return String(localized: "You're Offline")
            case .timedOut:
                return String(localized: "Request Timed Out")
            case .unauthorized:
                return String(localized: "Unable to Authenticate")
            case .server:
                return String(localized: "Server Error")
            case .decoding:
                return String(localized: "Unexpected Data")
            case .persistence:
                return String(localized: "Couldn't Save")
            case .missingAccessToken:
                return "Missing Access Token"
            case .invalidBaseURL:
                return "Invalid Movie Service Address"
            case .unknown:
                return String(localized: "Something Went Wrong")
        }
    }

    var message: String {
        switch self {
            case .offline:
                return String(localized: "Check your internet connection and try again.")
            case .timedOut:
                return String(localized: "The request took too long. Please try again.")
            case .unauthorized:
                return String(localized: "The movie service rejected this request. Check the access token.")
            case .server(let status) where status != 429 && (400..<500).contains(status):
                return String(localized: "The movie service couldn't find what you asked for (\(status)).")
            case .server(let status):
                return String(localized: "The movie service returned an error (\(status)). Please try again later.")
            case .decoding:
                return String(localized: "We couldn't understand the response from the movie service.")
            case .persistence:
                return String(localized: "Your change couldn't be saved. Please try again.")
            case .missingAccessToken:
                return "Copy Secrets.example.xcconfig to Secrets.xcconfig and set TMDB_ACCESS_TOKEN to the API Read Access Token on the TMDB API settings page. A v3 API key will not work."
            case .invalidBaseURL:
                return "Set TMDB_BASE_URL in Secrets.xcconfig to an https address, written as https:/$()/host/3, or remove it to call TMDB directly."
            case .unknown:
                return String(localized: "Please try again. If the problem continues, come back later.")
        }
    }

    /// Whether the UI offers a retry. A 4xx other than 429 means the request itself is
    /// wrong (for example a title TMDB removed), so asking again cannot succeed.
    var isRetryable: Bool {
        switch self {
            case .server(let status):
                return status == 429 || !(400..<500).contains(status)
            case .offline, .timedOut, .unknown, .decoding:
                return true
            case .unauthorized, .persistence, .missingAccessToken, .invalidBaseURL:
                return false
        }
    }

    /// Whether this failure was the connection itself, so the same request is worth
    /// sending again when the device comes back online.
    var retriesOnReconnect: Bool {
        self == .offline || self == .timedOut
    }
}
