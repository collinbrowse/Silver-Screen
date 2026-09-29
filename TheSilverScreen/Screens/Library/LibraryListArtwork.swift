//
//  LibraryListArtwork.swift
//  TheSilverScreen
//
//  Cover beside a library row. Watched and Watchlist are icons.
//  A custom list uses up to four images from the top of that list.
//

import Foundation

/// Row artwork for one library list.
enum LibraryListArtwork: Sendable, Equatable {
    case watched
    case watchlist
    /// Distinct image paths in the order the list shows its members. Empty when none have art.
    case images([String])

    /// Watched and Watchlist stay icons even when they contain titles.
    /// A custom list takes the first four distinct, non-blank paths in display order.
    static func cover(for list: LibraryList, entries: [ListEntry]) -> LibraryListArtwork {
        switch list.system {
            case .watched:
                return .watched
            case .watchlist:
                return .watchlist
            case nil:
                return .images(imagePaths(for: list, entries: entries))
        }
    }

    private static func imagePaths(for list: LibraryList, entries: [ListEntry]) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for entry in LibraryOrdering.displayed(entries, list: list) {
            let path = entry.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            paths.append(path)
            if paths.count == 4 { break }
        }
        return paths
    }
}
