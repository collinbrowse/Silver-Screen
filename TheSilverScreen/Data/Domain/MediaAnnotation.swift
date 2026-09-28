//
//  MediaAnnotation.swift
//  TheSilverScreen
//
//  A personal score and note for one movie, series, season, or episode.
//  Stored on device only; not a TMDB field.
//

import Foundation

enum AnnotationKind: String, Codable, Sendable, Equatable {
    case movie
    case tvSeries
    case tvSeason
    case tvEpisode
}

/// Identity for a personal score and note. Kind is part of the key so a movie id
/// never collides with a series id. Season number 0 is Specials.
struct AnnotationKey: Codable, Sendable, Equatable, Hashable {
    let kind: AnnotationKind
    let subjectID: Int
    let seasonNumber: Int
    let episodeNumber: Int

    static func movie(_ id: Int) -> AnnotationKey {
        AnnotationKey(kind: .movie, subjectID: id, seasonNumber: 0, episodeNumber: 0)
    }

    static func series(_ id: Int) -> AnnotationKey {
        AnnotationKey(kind: .tvSeries, subjectID: id, seasonNumber: 0, episodeNumber: 0)
    }

    static func season(seriesID: Int, seasonNumber: Int) -> AnnotationKey {
        AnnotationKey(kind: .tvSeason, subjectID: seriesID, seasonNumber: seasonNumber, episodeNumber: 0)
    }

    static func episode(seriesID: Int, seasonNumber: Int, episodeNumber: Int) -> AnnotationKey {
        AnnotationKey(
            kind: .tvEpisode,
            subjectID: seriesID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
    }
}

/// Half-point user score from 0.5 through 10. There is no zero and no way to clear a score.
enum UserScore {
    static let options: [Double] = (1...20).reversed().map { Double($0) / 2.0 }

    static func isValid(_ value: Double) -> Bool {
        let steps = (value * 2).rounded()
        guard abs(value * 2 - steps) < 0.001 else { return false }
        return (1...20).contains(Int(steps))
    }

    static func formatted(_ value: Double) -> String {
        String(format: "%.1f / 10", value)
    }

    static func accessibilityLabel(_ value: Double) -> String {
        String(format: "Your rating, %.1f out of 10", value)
    }
}

/// A saved personal score and the day it stands in for having been watched.
struct SavedUserScore: Sendable, Equatable {
    let formatted: String
    let ratedOn: String?
}

struct MediaAnnotation: Codable, Sendable, Equatable {
    let key: AnnotationKey
    var score: Double?
    var note: String?
    /// First day a score or note was saved. Later rating and note edits leave it alone.
    /// It stands in for the day the title was watched.
    var watchedAt: Date?

    init(key: AnnotationKey, score: Double?, note: String?, watchedAt: Date?) {
        self.key = key
        self.score = score
        self.note = note
        self.watchedAt = watchedAt
    }

    /// Drops an invalid score and a blank note. Nil when nothing personal remains.
    func normalized() -> MediaAnnotation? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = (trimmed?.isEmpty == false) ? trimmed : nil
        let cleanScore = score.flatMap { UserScore.isValid($0) ? $0 : nil }
        guard cleanScore != nil || cleanNote != nil else { return nil }
        return MediaAnnotation(key: key, score: cleanScore, note: cleanNote, watchedAt: watchedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case key, score, note, watchedAt, ratedAt, notedAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(AnnotationKey.self, forKey: .key)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        if let watchedAt = try container.decodeIfPresent(Date.self, forKey: .watchedAt) {
            self.watchedAt = watchedAt
            return
        }
        let ratedAt = try container.decodeIfPresent(Date.self, forKey: .ratedAt)
        let notedAt = try container.decodeIfPresent(Date.self, forKey: .notedAt)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        watchedAt = [ratedAt, notedAt, updatedAt].compactMap { $0 }.min()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(watchedAt, forKey: .watchedAt)
    }
}

/// Display values for the rating card and the description/notes section.
struct PersonalDetail: Sendable, Equatable {
    var formattedUserScore: String?
    var userScoreAccessibilityLabel: String
    var userNote: String?
    /// Day the title was first rated or noted, shown with the score.
    var formattedRatedOn: String?
    /// Same day, shown with the note.
    var formattedNotedOn: String?

    /// A saved note is the page shown when the detail screen appears.
    var showsNotesFirst: Bool { userNote != nil }

    static let empty = PersonalDetail(
        formattedUserScore: nil,
        userScoreAccessibilityLabel: "Add rating",
        userNote: nil,
        formattedRatedOn: nil,
        formattedNotedOn: nil
    )

    init(
        formattedUserScore: String?,
        userScoreAccessibilityLabel: String,
        userNote: String?,
        formattedRatedOn: String?,
        formattedNotedOn: String?
    ) {
        self.formattedUserScore = formattedUserScore
        self.userScoreAccessibilityLabel = userScoreAccessibilityLabel
        self.userNote = userNote
        self.formattedRatedOn = formattedRatedOn
        self.formattedNotedOn = formattedNotedOn
    }

    init(annotation: MediaAnnotation?, locale: Locale = .current) {
        let watchedOn = annotation?.watchedAt.map { DisplayDate.localDay($0, locale: locale) }
        let ratedOn = annotation?.watchedAt.map { DisplayDate.numericDay($0) }
        let notedOn = annotation?.note == nil ? nil : watchedOn
        if let score = annotation?.score {
            self.init(
                formattedUserScore: UserScore.formatted(score),
                userScoreAccessibilityLabel: UserScore.accessibilityLabel(score),
                userNote: annotation?.note,
                formattedRatedOn: ratedOn,
                formattedNotedOn: notedOn
            )
        } else {
            self.init(
                formattedUserScore: nil,
                userScoreAccessibilityLabel: "Add rating",
                userNote: annotation?.note,
                formattedRatedOn: nil,
                formattedNotedOn: notedOn
            )
        }
    }
}

enum AnnotationActivity {
    /// A successful personal save clears a previous save failure and leaves other activity alone.
    static func afterSuccess(_ activity: LoadActivity) -> LoadActivity {
        if case .failed(.persistence) = activity {
            return .none
        }
        return activity
    }
}
