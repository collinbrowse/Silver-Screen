//
//  LetterboxdImportViewModel.swift
//  SilverScreen
//
//  Drives Settings → Import from Letterboxd: read the picked export, match films on
//  TMDB, show what matched, then write it.
//

import Foundation

@Observable @MainActor
final class LetterboxdImportViewModel {
    /// Where the import is. Each step replaces the last, so the screen never shows a
    /// stale count next to a new phase.
    enum Phase: Equatable {
        /// Waiting for the person to pick the export.
        case choosing
        /// The picked files held no diary, ratings, watched, or watchlist rows.
        case nothingFound
        /// Searching TMDB, `done` of `total` films.
        case matching(done: Int, total: Int)
        /// Matched; waiting for the person to confirm.
        case review(LetterboxdImportReview)
        /// Writing, `done` of `total` films.
        case importing(done: Int, total: Int)
        case finished(LetterboxdImportSummary)
        /// Matching or writing stopped. The person can pick the export again.
        case failed(AppError)
    }

    private(set) var phase: Phase = .choosing

    private let importer: LetterboxdImporter
    /// Tells open screens the library changed once an import writes something.
    private let didImport: @MainActor () -> Void
    private var matches: [LetterboxdMatch] = []

    init(importer: LetterboxdImporter, didImport: @escaping @MainActor () -> Void = {}) {
        self.importer = importer
        self.didImport = didImport
    }

    /// Reads the files or folder the person picked, then matches like `load(files:)`.
    func load(urls: [URL]) async {
        await load(files: LetterboxdExport.read(urls: urls))
    }

    /// Reads the picked files and matches every film. Matching takes a while for a big
    /// export (a few films a second), so the phase carries progress.
    func load(files: [LetterboxdFile: String]) async {
        let plans = LetterboxdExport.plans(from: files)
        guard !plans.isEmpty else {
            phase = .nothingFound
            return
        }
        phase = .matching(done: 0, total: plans.count)
        do {
            matches = try await importer.match(plans) { [weak self] done in
                await self?.setPhase(.matching(done: done, total: plans.count))
            }
            phase = .review(LetterboxdImportReview(matches: matches))
        } catch is CancellationError {
            phase = .choosing
        } catch let error as AppError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unknown)
        }
    }

    /// Writes the matched films. Unmatched films are listed in the summary.
    func confirm() async {
        guard case .review = phase else { return }
        let total = matches.count
        phase = .importing(done: 0, total: total)
        do {
            let summary = try await importer.apply(matches) { [weak self] done in
                await self?.setPhase(.importing(done: done, total: total))
            }
            phase = .finished(summary)
            if summary.watchesAdded > 0 || summary.watchlistAdded > 0 {
                didImport()
            }
        } catch is CancellationError {
            phase = .review(LetterboxdImportReview(matches: matches))
        } catch let error as AppError {
            phase = .failed(error)
        } catch {
            phase = .failed(.persistence)
        }
    }

    /// Back to the picker, dropping any matches.
    func reset() {
        matches = []
        phase = .choosing
    }

    private func setPhase(_ next: Phase) {
        phase = next
    }
}

/// Counts for the confirm step.
struct LetterboxdImportReview: Equatable, Sendable {
    let matchedFilms: Int
    let watches: Int
    let ratings: Int
    let reviews: Int
    let watchlist: Int
    let unmatched: [LetterboxdFilm]

    init(matches: [LetterboxdMatch]) {
        let matched = matches.filter { $0.movie != nil }.map(\.plan)
        matchedFilms = matched.count
        watches = matched.reduce(0) { $0 + $1.watches.count }
        ratings = matched.reduce(0) { $0 + $1.watches.filter { $0.stars != nil }.count }
        reviews = matched.reduce(0) { $0 + $1.watches.filter { $0.review != nil }.count }
        watchlist = matched.filter { $0.onWatchlist && $0.watches.isEmpty }.count
        unmatched = matches.filter { $0.movie == nil }.map(\.plan.film)
    }
}
