//
//  AppInfo.swift
//  SilverScreen
//
//  Version identity and the outside links Settings shows.
//

import Foundation

/// Marketing version and build, read once from Info.plist.
struct AppInfo: Sendable, Equatable {
    let marketingVersion: String
    let build: String

    /// Reads `CFBundleShortVersionString` and `CFBundleVersion`. A missing key shows as `?`.
    static func from(infoDictionary: [String: Any]) -> AppInfo {
        func value(_ key: String) -> String {
            let raw = (infoDictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "?" : raw
        }
        return AppInfo(
            marketingVersion: value("CFBundleShortVersionString"),
            build: value("CFBundleVersion")
        )
    }

    /// The bundle's version, for the composition root.
    static func live(bundle: Bundle = .main) -> AppInfo {
        from(infoDictionary: bundle.infoDictionary ?? [:])
    }

    /// `0.1.1 (8)`, the way the App Store and TestFlight show a build.
    var versionLabel: String {
        "\(marketingVersion) (\(build))"
    }
}

/// Pages Settings links to. The privacy and support pages are GitHub Pages built from `docs/`.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://collinbrowse.github.io/Silver-Screen/privacy/")!
    static let support = URL(string: "https://collinbrowse.github.io/Silver-Screen/support/")!
    static let tmdb = URL(string: "https://www.themoviedb.org/")!
    static let justWatch = URL(string: "https://www.justwatch.com/")!
    static let wikidata = URL(string: "https://www.wikidata.org/")!
    static let imdb = URL(string: "https://www.imdb.com/")!
    static let sentryLicense = URL(string: "https://github.com/getsentry/sentry-cocoa/blob/main/LICENSE.md")!
}
