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

    var title: String {
        switch self {
            case .offline:
                return "You're Offline"
            case .timedOut:
                return "Request Timed Out"
            case .unauthorized:
                return "Unable to Authenticate"
            case .server:
                return "Server Error"
            case .decoding:
                return "Unexpected Data"
            case .persistence:
                return "Couldn't Save"
            case .missingAccessToken:
                return "Missing Access Token"
            case .invalidBaseURL:
                return "Invalid Movie Service Address"
            case .unknown:
                return "Something Went Wrong"
        }
    }

    var message: String {
        switch self {
            case .offline:
                return "Check your internet connection and try again."
            case .timedOut:
                return "The request took too long. Please try again."
            case .unauthorized:
                return "The movie service rejected this request. Check the access token."
            case .server(let status) where status != 429 && (400..<500).contains(status):
                return "The movie service couldn't find what you asked for (\(status))."
            case .server(let status):
                return "The movie service returned an error (\(status)). Please try again later."
            case .decoding:
                return "We couldn't understand the response from the movie service."
            case .persistence:
                return "Your change couldn't be saved. Please try again."
            case .missingAccessToken:
                return "Copy Secrets.example.xcconfig to Secrets.xcconfig and set TMDB_ACCESS_TOKEN to the API Read Access Token on the TMDB API settings page. A v3 API key will not work."
            case .invalidBaseURL:
                return "Set TMDB_BASE_URL in Secrets.xcconfig to an https address, written as https:/$()/host/3, or remove it to call TMDB directly."
            case .unknown:
                return "Please try again. If the problem continues, come back later."
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
}
