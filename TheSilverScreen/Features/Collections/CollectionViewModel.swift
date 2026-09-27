//
//  CollectionViewModel.swift
//  TheSilverScreen
//

import Foundation

struct CollectionContent: Sendable, Equatable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let parts: [CatalogMovieRow]
}

/// Loads one movie collection: header plus the parts list.
@Observable
@MainActor
final class CollectionViewModel {
    private(set) var state: LoadState<CollectionContent> = .idle

    private let collectionID: Int
    private let movies: MovieRepository
    private let annotations: AnnotationsRepository

    init(collectionID: Int, movies: MovieRepository, annotations: AnnotationsRepository) {
        self.collectionID = collectionID
        self.movies = movies
        self.annotations = annotations
    }

    func load() async {
        state = .loading
        do {
            let collection = try await movies.collection(id: collectionID)
            let poster = collection.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let posterPath = (poster?.isEmpty == false) ? poster : nil
            let overview = collection.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = collection.parts
                .sorted(by: Self.undatedFirst)
                .map(CatalogMovieRow.init)
            if posterPath == nil, overview.isEmpty, parts.isEmpty {
                state = .empty
                return
            }
            let content = CollectionContent(
                id: collection.id,
                name: collection.name,
                overview: overview,
                posterPath: posterPath,
                parts: parts
            )
            state = .loaded(content)
            await reloadDisplayedScores()
        } catch is CancellationError {
            return
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    func retry() async {
        await load()
    }

    func noteListSaveFailed() {
        guard case .loaded(let content, _) = state else { return }
        state = .loaded(content, activity: .failed(.persistence))
    }

    /// Writes saved scores onto the parts already on screen.
    func reloadDisplayedScores() async {
        guard case .loaded(let content, let activity) = state else { return }
        let scores = await annotations.formattedScores()
        let parts = content.parts.map { $0.withUserScore(scores[.movie($0.id)]) }
        guard parts != content.parts else { return }
        state = .loaded(
            CollectionContent(
                id: content.id,
                name: content.name,
                overview: content.overview,
                posterPath: content.posterPath,
                parts: parts
            ),
            activity: activity
        )
    }

    /// Missing release dates sort ahead of every dated part. Dated parts go oldest first.
    private static func undatedFirst(_ lhs: Movie, _ rhs: Movie) -> Bool {
        switch (lhs.releaseDate, rhs.releaseDate) {
        case (nil, nil):
            return lhs.id < rhs.id
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case let (left?, right?) where left != right:
            return left < right
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
