//
//  MediaTypes.swift
//  TheSilverScreen
//
//  Created by Collin Browse on 10/2/26.
//

enum MediaTypes: String, CaseIterable, Sendable, Equatable {
    case all
    case movies
    case tv

    var title: String {
        switch self {
            case .all: "All"
            case .movies: "Movies"
            case .tv: "TV Series"
        }
    }

    var symbol: String {
        switch self {
            case .all: "square.grid.2x2"
            case .movies: "film"
            case .tv: "tv"
        }
    }
}
