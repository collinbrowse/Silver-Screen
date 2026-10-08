//
//  SearchListing.swift
//  TheSilverScreen
//
//  Unified search payloads: typeahead preview sections and interleaved View-all rows.
//

import Foundation

/// One hit in a mixed Movies / TV / People search list.
enum SearchResultItem: Sendable, Equatable, Identifiable {
    case movie(CatalogMovieRow)
    case tv(CatalogTVRow)
    case person(CatalogPersonRow)

    /// Composite so a movie id and a TV id never collide in a List.
    var id: String {
        switch self {
            case .movie(let row): "m-\(row.id)"
            case .tv(let row): "t-\(row.id)"
            case .person(let row): "p-\(row.id)"
        }
    }

    var popularity: Double {
        switch self {
            case .movie(let row): row.popularity
            case .tv(let row): row.popularity
            case .person(let row): row.popularity
        }
    }

    var displayName: String {
        switch self {
            case .movie(let row): row.title
            case .tv(let row): row.name
            case .person(let row): row.name
        }
    }

    func withUserScore(_ scores: [AnnotationKey: SavedUserScore]) -> SearchResultItem {
        switch self {
            case .movie(let row):
                .movie(row.withUserScore(scores[.movie(row.id)]))
            case .tv(let row):
                .tv(row.withUserScore(scores[.series(row.id)]))
            case .person:
                self
        }
    }
}

/// Whether People float above Movies/TV for one committed query's results.
/// Decided from the first successful page and then frozen — never flipped on screen.
enum SearchResultEmphasis: Sendable, Equatable {
    /// Preview / blocks: Movies, then TV, then People.
    case titlesFirst
    /// Preview / blocks: People, then Movies, then TV.
    case peopleFirst
}

/// Picks emphasis by comparing the strongest fuzzy-matched person to the strongest matched title.
enum SearchResultEmphasisResolver {
    static func emphasis(
        movies: [SearchResultItem],
        tv: [SearchResultItem],
        people: [SearchResultItem],
        query: String
    ) -> SearchResultEmphasis {
        let matchingPeople = people.filter {
            FuzzyTextMatch.matches(query: query, candidate: $0.displayName)
        }
        guard let bestPerson = matchingPeople.max(by: { $0.popularity < $1.popularity }) else {
            return .titlesFirst
        }
        let matchingTitles = (movies + tv).filter {
            FuzzyTextMatch.matches(query: query, candidate: $0.displayName)
        }
        guard let bestTitle = matchingTitles.max(by: { $0.popularity < $1.popularity }) else {
            return .peopleFirst
        }
        return bestPerson.popularity >= bestTitle.popularity ? .peopleFirst : .titlesFirst
    }
}

/// Capped typeahead sections shown before View all.
struct SearchPreviewSections: Sendable, Equatable {
    var movies: [CatalogMovieRow]
    var tv: [CatalogTVRow]
    var people: [CatalogPersonRow]
    /// Frozen with the query cache so section order does not flash after first paint.
    var emphasis: SearchResultEmphasis = .titlesFirst

    var isEmpty: Bool {
        movies.isEmpty && tv.isEmpty && people.isEmpty
    }

    func applying(_ scores: [AnnotationKey: SavedUserScore]) -> SearchPreviewSections {
        SearchPreviewSections(
            movies: movies.map { $0.withUserScore(scores[.movie($0.id)]) },
            tv: tv.map { $0.withUserScore(scores[.series($0.id)]) },
            people: people,
            emphasis: emphasis
        )
    }
}

/// What the Search screen shows for a committed query.
enum SearchContent: Sendable, Equatable {
    case preview(SearchPreviewSections)
    case allResults([SearchResultItem])

    var isEmpty: Bool {
        switch self {
            case .preview(let sections): sections.isEmpty
            case .allResults(let items): items.isEmpty
        }
    }

    func applying(_ scores: [AnnotationKey: SavedUserScore]) -> SearchContent {
        switch self {
            case .preview(let sections):
                .preview(sections.applying(scores))
            case .allResults(let items):
                .allResults(items.map { $0.withUserScore(scores) })
        }
    }
}
