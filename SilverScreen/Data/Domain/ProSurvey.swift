//
//  ProSurvey.swift
//  SilverScreen
//
//  The "Pro is coming soon" survey: which features people would want in a paid
//  tier. It tests demand before any Pro work starts. Answers go to the survey
//  endpoint on the Worker (worker/src/survey.js) and are analyzed in D1.
//

import Foundation

/// Survey-wide constants.
enum ProSurvey {
    /// Stored with every answer. Bump it when the options change enough that old
    /// answers should be counted apart from new ones.
    static let id = "pro-features-1"
    /// Matches `SURVEY_MAX_OTHER_CHARS` in the Worker.
    static let otherCharacterLimit = 500
}

/// A feature the survey offers. Raw values are what the Worker stores and the
/// report counts, so never rename one; add a new case instead.
enum ProFeature: String, CaseIterable, Sendable, Identifiable {
    case widgets
    case stats
    case episodeAlerts
    case streamingServices
    case sync
    case friends
    case appIcons
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
            case .widgets: "Home Screen Widgets"
            case .stats: "Stats and Year in Review"
            case .episodeAlerts: "New Episode Alerts"
            case .streamingServices: "My Streaming Services"
            case .sync: "Sync Across Devices"
            case .friends: "Friends and Shared Lists"
            case .appIcons: "App Icons and Themes"
            case .export: "Export Your Library"
        }
    }

    var detail: String {
        switch self {
            case .widgets: "Your next episode and a Watchlist pick"
            case .stats: "Hours watched, top genres, and your year in film and TV"
            case .episodeAlerts: "A notification when a show you're watching airs"
            case .streamingServices: "Filter to your services, and hear when a Watchlist title arrives"
            case .sync: "Your library on iPhone and iPad"
            case .friends: "Follow friends and build lists together"
            case .appIcons: "Alternate icons and color themes"
            case .export: "Your lists, ratings, and notes as CSV or JSON"
        }
    }

    var systemImage: String {
        switch self {
            case .widgets: "square.grid.2x2"
            case .stats: "chart.bar.xaxis"
            case .episodeAlerts: "bell.badge"
            case .streamingServices: "play.tv"
            case .sync: "arrow.triangle.2.circlepath"
            case .friends: "person.2"
            case .appIcons: "app.badge"
            case .export: "square.and.arrow.up"
        }
    }

    /// Every option in an order fixed for one install. Lists read top-down get more
    /// picks near the top, so each install sees its own order, and reopening the
    /// survey shows the same one.
    static func displayOrder(seed: UInt64) -> [ProFeature] {
        var generator = SplitMix64(seed: seed)
        return allCases.shuffled(using: &generator)
    }
}

/// Where the survey was opened. Raw values match `SURVEY_SOURCES` in the Worker.
enum ProSurveySource: String, Sendable {
    case settings
    case libraryCard
}

/// One person's answers. `other` is trimmed, and nil when blank.
struct ProSurveyAnswers: Sendable, Equatable {
    let features: Set<ProFeature>
    let other: String?
}

/// A small seeded generator, so the option order is stable per install and testable.
/// Not for anything that needs real randomness.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
