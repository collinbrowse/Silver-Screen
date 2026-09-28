//
//  ListItemDraft.swift
//  TheSilverScreen
//
//  Builds the snapshot written when a title is added to a list. Values come from
//  the model already on screen. Missing numbers stay zero; nothing is fetched.
//

import Foundation

extension Movie {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .movie,
            title: title,
            imagePath: posterPath,
            releaseDate: releaseDate,
            genreNames: MovieGenreCatalog.names(for: genreIDs),
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

extension MovieDetail {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .movie,
            title: title,
            imagePath: posterPath,
            releaseDate: releaseDate,
            genreNames: genres.map(\.name),
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

extension TVSeriesSummary {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .tv,
            title: name,
            imagePath: posterPath,
            releaseDate: firstAirDate,
            genreNames: TVGenreCatalog.names(for: genreIDs),
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

extension TVSeriesDetail {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .tv,
            title: name,
            imagePath: posterPath,
            releaseDate: firstAirDate,
            genreNames: genres.map(\.name),
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

extension PersonSummary {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .person,
            title: name,
            imagePath: profilePath,
            releaseDate: nil,
            genreNames: departmentNames(knownForDepartment),
            voteAverage: 0,
            popularity: popularity
        )
    }
}

extension PersonDetail {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .person,
            title: name,
            imagePath: profilePath,
            releaseDate: nil,
            genreNames: departmentNames(knownForDepartment),
            voteAverage: 0,
            popularity: popularity
        )
    }
}

extension PersonCredit {
    /// Movie or series credit. The person's own list membership is a separate draft.
    func listItem() -> ListItemDraft {
        switch mediaType {
        case .movie:
            ListItemDraft(
                id: mediaID,
                kind: .movie,
                title: title,
                imagePath: posterPath,
                releaseDate: releaseDate,
                genreNames: MovieGenreCatalog.names(for: genreIDs),
                voteAverage: voteAverage,
                popularity: popularity
            )
        case .tv:
            ListItemDraft(
                id: mediaID,
                kind: .tv,
                title: title,
                imagePath: posterPath,
                releaseDate: releaseDate,
                genreNames: TVGenreCatalog.names(for: genreIDs),
                voteAverage: voteAverage,
                popularity: popularity
            )
        }
    }
}

extension CastMember {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: personID,
            kind: .person,
            title: name,
            imagePath: profilePath,
            releaseDate: nil,
            genreNames: departmentNames(knownForDepartment),
            voteAverage: 0,
            popularity: 0
        )
    }
}

extension CreditedPerson {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .person,
            title: name,
            imagePath: profilePath,
            releaseDate: nil,
            genreNames: departmentNames(knownForDepartment),
            voteAverage: 0,
            popularity: 0
        )
    }
}

extension BrowseRow {
    func listItem() -> ListItemDraft {
        switch media {
        case .movie:
            ListItemDraft(
                id: mediaID,
                kind: .movie,
                title: title,
                imagePath: posterPath,
                releaseDate: date,
                genreNames: genreNames,
                voteAverage: voteAverage,
                popularity: popularity
            )
        case .tv:
            ListItemDraft(
                id: mediaID,
                kind: .tv,
                title: title,
                imagePath: posterPath,
                releaseDate: date,
                genreNames: genreNames,
                voteAverage: voteAverage,
                popularity: popularity
            )
        }
    }
}

extension CatalogMovieRow {
    func listItem() -> ListItemDraft {
        asMovie().listItem()
    }
}

extension CatalogTVRow {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .tv,
            title: name,
            imagePath: posterPath,
            releaseDate: firstAirDate,
            genreNames: genreNames,
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

extension CatalogPersonRow {
    func listItem() -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .person,
            title: name,
            imagePath: profilePath,
            releaseDate: nil,
            genreNames: departmentNames(knownForDepartment),
            voteAverage: 0,
            popularity: popularity
        )
    }
}

private func departmentNames(_ department: String?) -> [String] {
    guard let department = department?.trimmingCharacters(in: .whitespacesAndNewlines),
          !department.isEmpty else {
        return []
    }
    return [department]
}
