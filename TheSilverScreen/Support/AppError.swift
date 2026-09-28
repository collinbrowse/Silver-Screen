//
//  AppError.swift
//  TheSilverScreen
//

import Foundation

enum AppError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case unauthorized
    case server(status: Int)
    case decoding
    case persistence
    case missingAPIKey
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
        case .missingAPIKey:
            return "Missing API Key"
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
            return "The movie service rejected this request. Check your API key."
        case .server(let status):
            return "The movie service returned an error (\(status)). Please try again later."
        case .decoding:
            return "We couldn't understand the response from the movie service."
        case .persistence:
            return "Your change couldn't be saved. Please try again."
        case .missingAPIKey:
            return "Copy Secrets.example.xcconfig to Secrets.xcconfig and set TMDB_API_KEY."
        case .unknown:
            return "Please try again. If the problem continues, come back later."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .server, .unknown, .decoding:
            return true
        case .unauthorized, .persistence, .missingAPIKey:
            return false
        }
    }
}
