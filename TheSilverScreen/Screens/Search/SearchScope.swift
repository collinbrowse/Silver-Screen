//
//  SearchScope.swift
//  TheSilverScreen
//

import Foundation

enum SearchScope: String, CaseIterable, Sendable, Equatable {
    case movies
    case tv
    case people

    var title: String {
        switch self {
            case .movies: "Movies"
            case .tv: "TV"
            case .people: "People"
        }
    }
}
