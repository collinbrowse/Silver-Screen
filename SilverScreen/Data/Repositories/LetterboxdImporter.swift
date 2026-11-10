//
//  LetterboxdImporter.swift
//  SilverScreen
//
//  Turns a Letterboxd export into Silver Screen watches: matches each film to a TMDB
//  movie by name and year, then logs its diary watches (dates, ratings, rewatches,
//  reviews) and watchlist through the same repositories the app writes with.
//  Importing the same export twice adds nothing the second time.
//

import Foundation

/// A film from the export and the TMDB movie it matched, if any.
struct LetterboxdMatch: Sendable, Equatable {
    let plan: LetterboxdFilmPlan
    let movie: Movie?
}

/// What an import changed, for the summary screen.
struct LetterboxdImportSummary: Sendable, Equatable {
    /// Diary watches written.
    var watchesAdded = 0
    /// Films that gained at least one watch (and so are on Watched).
    var filmsLogged = 0
    var watchlistAdded = 0
    /// Matched films the library already had everything for.
    var alreadyInLibrary = 0
    /// Films TMDB search found nothing for, so nothing was written.
    var unmatched: [LetterboxdFilm] = []
    /// Films whose write failed; the rest of the import went ahead.
    var failed = 0
}

actor LetterboxdImporter {
    private let movies: MovieRepository
    private let watches: WatchRepository
    private let lists: ListsRepository
    private let logger: any AppLogging
    private let sleeper: any Sleeper
    /// Pause between searches. The TMDB proxy allows 240 requests a minute per IP.
    private let spacing: TimeInterval
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        movies: MovieRepository,
        watches: WatchRepository,
        lists: ListsRepository,
        logger: any AppLogging,
        sleeper: any Sleeper = TaskSleeper(),
        spacing: TimeInterval = 0.3,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.movies = movies
        self.watches = watches
        self.lists = lists
        self.logger = logger
        self.sleeper = sleeper
        self.spacing = spacing
        self.now = now
        self.calendar = calendar
    }

    /// Searches TMDB for every film, one at a time and spaced out. `progress` gets the
    /// count finished so far. A film whose search fails or finds nothing comes back
    /// with no movie. Being offline stops the whole match with `AppError.offline`.
    func match(
        _ plans: [LetterboxdFilmPlan],
        progress: @Sendable (Int) async -> Void = { _ in }
    ) async throws -> [LetterboxdMatch] {
        var matches: [LetterboxdMatch] = []
        for (index, plan) in plans.enumerated() {
            try Task.checkCancellation()
            if index > 0 {
                try await sleeper.sleep(seconds: spacing)
            }
            let movie: Movie?
            do {
                movie = try await search(plan.film)
            } catch let error as AppError where error == .offline {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("Letterboxd match search failed", category: .networking)
                movie = nil
            }
            matches.append(LetterboxdMatch(plan: plan, movie: movie))
            await progress(index + 1)
        }
        return matches
    }

    /// Writes every matched film. Each film is its own write, so one failure is counted
    /// and the import carries on. `progress` gets the count finished so far.
    func apply(
        _ matches: [LetterboxdMatch],
        progress: @Sendable (Int) async -> Void = { _ in }
    ) async throws -> LetterboxdImportSummary {
        var summary = LetterboxdImportSummary()
        let watchlistID = try await lists.snapshot().list(.watchlist)?.id
        for (index, match) in matches.enumerated() {
            try Task.checkCancellation()
            guard let movie = match.movie else {
                summary.unmatched.append(match.plan.film)
                await progress(index + 1)
                continue
            }
            do {
                try await write(match.plan, movie: movie, watchlistID: watchlistID, into: &summary)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("Letterboxd import write failed for movie \(movie.id)", category: .persistence)
                summary.failed += 1
            }
            await progress(index + 1)
        }
        return summary
    }

    // MARK: - Matching

    /// The best TMDB movie for a Letterboxd film: an exact year match first (an exact
    /// title among those), then a year off by one (release dates differ by country),
    /// then, for a film with no year, the top result.
    private func search(_ film: LetterboxdFilm) async throws -> Movie? {
        let page = try await movies.searchMovies(query: film.name, page: 1, year: film.year)
        if let best = Self.bestMatch(for: film, in: page.movies, yearTolerance: 0) {
            return best
        }
        guard film.year != nil else { return nil }
        try await sleeper.sleep(seconds: spacing)
        let loose = try await movies.searchMovies(query: film.name, page: 1)
        return Self.bestMatch(for: film, in: loose.movies, yearTolerance: 1)
    }

    /// Picks from search results. Exact title (ignoring case and accents) wins over TMDB's
    /// order; nil when no result is within `yearTolerance` of the film's year.
    nonisolated static func bestMatch(
        for film: LetterboxdFilm,
        in results: [Movie],
        yearTolerance: Int
    ) -> Movie? {
        let candidates: [Movie]
        if let year = film.year {
            candidates = results.filter { movie in
                guard let released = DisplayDate.year(movie.releaseDate).flatMap(Int.init) else { return false }
                return abs(released - year) <= yearTolerance
            }
        } else {
            candidates = results
        }
        let wanted = normalizedTitle(film.name)
        return candidates.first { normalizedTitle($0.title) == wanted } ?? candidates.first
    }

    private nonisolated static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Writing

    private func write(
        _ plan: LetterboxdFilmPlan,
        movie: Movie,
        watchlistID: UUID?,
        into summary: inout LetterboxdImportSummary
    ) async throws {
        let draft = movie.listItem()
        let entries = plan.watches.map { diaryEntry(for: $0, movie: movie) }
        var wroteSomething = false
        if !entries.isEmpty {
            let added = try await watches.importMovieWatches(draft, entries: entries)
            if added > 0 {
                summary.watchesAdded += added
                summary.filmsLogged += 1
                wroteSomething = true
            }
        }
        // Watched wins over the watchlist, as it does when someone logs a watchlist title.
        if plan.onWatchlist, plan.watches.isEmpty, let watchlistID,
           try await watches.watches(of: .movie(movie.id)).isEmpty {
            let snapshot = try await lists.snapshot()
            let alreadyListed = snapshot.entries.contains { $0.listID == watchlistID && $0.itemKey == draft.itemKey }
            if !alreadyListed {
                _ = try await lists.add(draft: draft, listID: watchlistID, at: now())
                summary.watchlistAdded += 1
                wroteSomething = true
            }
        }
        if !wroteSomething {
            summary.alreadyInLibrary += 1
        }
    }

    private func diaryEntry(for watch: LetterboxdWatch, movie: Movie) -> DiaryEntry {
        let loggedAt = now()
        return DiaryEntry(
            id: UUID(),
            subject: .movie(movie.id),
            title: movie.title,
            releaseYear: DisplayDate.year(movie.releaseDate).flatMap(Int.init),
            posterPath: movie.posterPath,
            watchedOn: watch.watchedOn ?? DiaryDay(loggedAt, calendar: calendar),
            score: watch.stars.flatMap(LetterboxdRating.score(fromStars:)),
            review: watch.review,
            isRewatch: watch.isRewatch,
            loggedAt: loggedAt,
            isDateKnown: watch.watchedOn != nil
        )
    }
}
