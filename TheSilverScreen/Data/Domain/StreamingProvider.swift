//
//  StreamingProvider.swift
//  TheSilverScreen
//
//  A subscription streaming service where a title is available to watch.
//

import Foundation

/// One flatrate provider from TMDB watch-provider data for the user's region.
struct StreamingProvider: Sendable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
    /// TMDB relative path (e.g. `/abc.png`), loaded from `image.tmdb.org/t/p/…` as a logo.
    let logoPath: String?
}
