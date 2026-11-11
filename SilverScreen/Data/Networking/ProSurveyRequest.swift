//
//  ProSurveyRequest.swift
//  SilverScreen
//
//  The POST that sends survey answers to the Worker's /survey route
//  (worker/src/survey.js). The Worker is the same host as the TMDB proxy, so the
//  survey only exists in builds that call TMDB through the proxy.
//

import Foundation

/// The body the Worker validates. Field names are the Worker's.
struct ProSurveySubmissionDTO: Encodable, Equatable, Sendable {
    let surveyID: String
    /// Random per install and survey, so changing answers replaces the stored row.
    let responseID: String
    /// Sorted feature raw values.
    let features: [String]
    let other: String?
    let source: String
    let appVersion: String
    let build: String
    /// True in Debug builds, so test answers stay out of the counts.
    let isTest: Bool
}

enum ProSurveyRequest {
    static let path = "/survey"

    /// `https://<proxy host>/survey`, or nil when the app calls TMDB directly and has no Worker.
    static func endpoint(for connection: TMDBConnection) -> URL? {
        guard connection.accessToken == nil,
              var components = URLComponents(url: connection.baseURL, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func make(_ body: ProSurveySubmissionDTO, endpoint: URL) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }
}
