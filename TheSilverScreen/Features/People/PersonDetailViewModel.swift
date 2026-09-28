//
//  PersonDetailViewModel.swift
//  TheSilverScreen
//

import Foundation

struct PersonDetailContent: Sendable, Equatable {
    struct ImagesSection: Sendable, Equatable {
        let items: [MovieImage]
    }

    /// Carousel + optional View All for cast or crew credits.
    struct CreditsSection: Sendable, Equatable {
        let department: CreditDepartment
        /// First five credits shown in the carousel.
        let preview: [PersonCredit]
        let totalCount: Int
        /// True when totalCount > 10 (requirement threshold for View All).
        var showsViewAll: Bool { totalCount > 10 }
    }

    let detail: PersonDetail
    let formattedBirthday: String?
    let formattedDeathday: String?
    let placeOfBirth: String?
    let images: ImagesSection?
    let cast: CreditsSection?
    let crew: CreditsSection?

    /// Non-nil while the image lightbox is open.
    var fullscreenImages: FullscreenImages?
}

@Observable
@MainActor
final class PersonDetailViewModel {
    private(set) var state: LoadState<PersonDetailContent> = .idle

    private let personID: Int
    private let people: PersonRepository

    init(personID: Int, people: PersonRepository) {
        self.personID = personID
        self.people = people
    }

    func load() async {
        state = .loading

        do {
            let detail = try await people.personDetail(id: personID)
            let content = Self.makeContent(detail: detail)
            state = .loaded(content)
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

    func openImages(initialID: String) {
        guard case .loaded(let content, let activity) = state,
              let images = content.images else { return }
        state = .loaded(
            content.withFullscreen(
                FullscreenImages(initialID: initialID, images: images.items, kind: .profile)
            ),
            activity: activity
        )
    }

    func openProfile() {
        guard case .loaded(let content, let activity) = state,
              let path = content.detail.profilePath,
              !path.isEmpty else { return }
        let profile = MovieImage(filePath: path, voteAverage: 0)
        state = .loaded(
            content.withFullscreen(
                FullscreenImages(initialID: path, images: [profile], kind: .profile)
            ),
            activity: activity
        )
    }

    func dismissImages() {
        guard case .loaded(let content, let activity) = state else { return }
        state = .loaded(content.withFullscreen(nil), activity: activity)
    }

    static func makeContent(detail: PersonDetail) -> PersonDetailContent {
        let images = detail.images.isEmpty
            ? nil
            : PersonDetailContent.ImagesSection(items: detail.images)
        let cast = makeCreditsSection(detail.castCredits, department: .cast)
        let crew = makeCreditsSection(detail.crewCredits, department: .crew)

        return PersonDetailContent(
            detail: detail,
            formattedBirthday: formatDay(detail.birthday),
            formattedDeathday: formatDay(detail.deathday),
            placeOfBirth: detail.placeOfBirth,
            images: images,
            cast: cast,
            crew: crew,
            fullscreenImages: nil
        )
    }

    /// Genre names for a credit row, using the movie or TV catalog by media type.
    static func genreNames(for credit: PersonCredit) -> [String] {
        switch credit.mediaType {
        case .movie: return MovieGenreCatalog.names(for: credit.genreIDs)
        case .tv: return TVGenreCatalog.names(for: credit.genreIDs)
        }
    }

    static func formatDay(_ date: Date?) -> String? {
        guard let date else { return nil }
        return DisplayDate.day(date)
    }

    static func formatReleaseDate(_ date: Date?) -> String {
        guard date != nil else { return "Not available" }
        return DisplayDate.day(date)
    }

    // MARK: - Private

    private static func makeCreditsSection(
        _ credits: [PersonCredit],
        department: CreditDepartment
    ) -> PersonDetailContent.CreditsSection? {
        guard !credits.isEmpty else { return nil }
        return PersonDetailContent.CreditsSection(
            department: department,
            preview: Array(credits.prefix(5)),
            totalCount: credits.count
        )
    }
}

private extension PersonDetailContent {
    func copy(
        fullscreenImages: FullscreenImages?? = nil
    ) -> PersonDetailContent {
        PersonDetailContent(
            detail: detail,
            formattedBirthday: formattedBirthday,
            formattedDeathday: formattedDeathday,
            placeOfBirth: placeOfBirth,
            images: images,
            cast: cast,
            crew: crew,
            fullscreenImages: fullscreenImages ?? self.fullscreenImages
        )
    }

    func withFullscreen(_ fullscreen: FullscreenImages?) -> PersonDetailContent {
        copy(fullscreenImages: .some(fullscreen))
    }
}
