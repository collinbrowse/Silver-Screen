//
//  PersonDetailViewModel.swift
//  SilverScreen
//

import Foundation

struct PersonDetailContent: Sendable, Equatable {
    struct ImagesSection: Sendable, Equatable {
        let items: [MovieImage]
    }

    /// Carousel + optional View All for one slice of this person's credits.
    struct CreditsSection: Sendable, Equatable, Identifiable {
        let department: CreditDepartment
        /// Heading such as Directing, Acting, or Crew.
        let title: String
        /// Every credit in this slice, in display order. The carousel shows a
        /// width-dependent prefix; see `CarouselMetrics`.
        let credits: [PersonCredit]
        var totalCount: Int { credits.count }
        var id: CreditDepartment { department }

        /// The first `count` credits, for the carousel.
        func preview(count: Int) -> [PersonCredit] {
            Array(credits.prefix(count))
        }

        /// Whether View All leads to more than a carousel showing `previewCount` holds.
        func showsViewAll(previewCount: Int) -> Bool {
            CarouselMetrics.showsViewAll(totalCount: totalCount, previewCount: previewCount)
        }

        /// The phone carousel: the first `CarouselMetrics.compactPreviewCount` credits.
        var preview: [PersonCredit] {
            preview(count: CarouselMetrics.compactPreviewCount)
        }

        /// View All on a phone, where the carousel shows `preview`.
        var showsViewAll: Bool {
            showsViewAll(previewCount: CarouselMetrics.compactPreviewCount)
        }
    }

    let detail: PersonDetail
    let formattedBirthday: String?
    let formattedDeathday: String?
    let placeOfBirth: String?
    let images: ImagesSection?
    /// Carousels in display order. The work this person is known for leads.
    let creditSections: [CreditsSection]
    /// Prizes given to this person for a title. The section is hidden when empty.
    let awards: [PersonAward]

    /// Non-nil while the image lightbox is open.
    var fullscreenImages: FullscreenImages?
}

@Observable
@MainActor
final class PersonDetailViewModel {
    private(set) var state: LoadState<PersonDetailContent> = .idle
    /// Personal scores for credit posters (carousel badges), keyed by credit id.
    private(set) var creditUserScores: [String: String] = [:]

    private let personID: Int
    private let people: PersonRepository
    private let annotations: AnnotationsRepository?
    private let awards: AwardsRepository

    init(
        personID: Int,
        people: PersonRepository,
        annotations: AnnotationsRepository? = nil,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.personID = personID
        self.people = people
        self.annotations = annotations
        self.awards = awards
    }

    func load() async {
        state = .loading

        do {
            let detail = try await people.personDetail(id: personID)
            let personAwards = await awards.personAwards(imdbID: detail.imdbID)
            let content = Self.makeContent(detail: detail, awards: personAwards)
            state = .loaded(content)
            await reloadCreditUserScores(content)
        } catch is CancellationError {
            // The view only starts a load from `.idle`, so a load cancelled by a tab switch must
            // go back to `.idle` or the screen keeps its spinner forever.
            if case .loading = state { state = .idle }
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    func userScore(for credit: PersonCredit) -> String? {
        creditUserScores[credit.id]
    }

    private func reloadCreditUserScores(_ content: PersonDetailContent) async {
        guard let annotations else {
            creditUserScores = [:]
            return
        }
        let scores = await annotations.formattedScores()
        var mapped: [String: String] = [:]
        for section in content.creditSections {
            for credit in section.credits {
                let key: AnnotationKey = switch credit.mediaType {
                    case .movie: .movie(credit.mediaID)
                    case .tv: .series(credit.mediaID)
                }
                if let formatted = scores[key]?.formatted {
                    mapped[credit.id] = formatted
                }
            }
        }
        creditUserScores = mapped
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

    static func makeContent(detail: PersonDetail, awards: [PersonAward] = []) -> PersonDetailContent {
        let images = detail.images.isEmpty
            ? nil
            : PersonDetailContent.ImagesSection(items: detail.images)
        let creditSections = PersonCreditGroups.make(from: detail).map { group in
            PersonDetailContent.CreditsSection(
                department: group.department,
                title: group.title,
                credits: group.credits
            )
        }

        return PersonDetailContent(
            detail: detail,
            formattedBirthday: formatDay(detail.birthday),
            formattedDeathday: formatDay(detail.deathday),
            placeOfBirth: detail.placeOfBirth,
            images: images,
            creditSections: creditSections,
            awards: awards,
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

}

/// Orders a person's credits so the work they are known for leads the page.
enum PersonCreditGroups {
    struct Group: Sendable, Equatable {
        let department: CreditDepartment
        let title: String
        let credits: [PersonCredit]
    }

    /// Acting, or an unknown department, leads. A director, writer, or other crew
    /// department leads with that work, then acting, then any jobs left over.
    /// An empty primary slice is omitted, so a director with no director credits
    /// still shows acting and the rest of their crew.
    static func make(from detail: PersonDetail) -> [Group] {
        let known = trimmed(detail.knownForDepartment)
        let leadsWithActing = known.map(isActing) ?? true

        var groups: [Group] = []
        var consumed = Set<String>()

        if leadsWithActing {
            if let acting = actingGroup(detail.castCredits) {
                groups.append(acting)
            }
        } else if let known, let primary = primaryGroup(known: known, credits: detail.crewCredits) {
            groups.append(primary.group)
            consumed = primary.consumed
        }

        if !leadsWithActing, let acting = actingGroup(detail.castCredits) {
            groups.append(acting)
        }

        if let crew = leftoverCrew(detail.crewCredits, consumed: consumed) {
            groups.append(crew)
        }
        return groups
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func isActing(_ name: String) -> Bool {
        switch name.lowercased() {
            case "acting", "actors": return true
            default: return false
        }
    }

    private static func actingGroup(_ credits: [PersonCredit]) -> Group? {
        guard !credits.isEmpty else { return nil }
        return Group(department: .cast, title: "Acting", credits: credits)
    }

    private static func primaryGroup(
        known: String,
        credits: [PersonCredit]
    ) -> (group: Group, consumed: Set<String>)? {
        switch known.lowercased() {
            case "directing":
                return slice(credits, department: .directing, title: "Directing") { $0.job == "Director" }
            case "writing":
                return slice(credits, department: .writing, title: "Writing") {
                MovieRepository.writerJobs.contains($0.job)
                }
            default:
                return slice(credits, department: .named(known), title: known) { job in
                !job.department.isEmpty && job.department.caseInsensitiveCompare(known) == .orderedSame
                }
        }
    }

    private static func slice(
        _ credits: [PersonCredit],
        department: CreditDepartment,
        title: String,
        where matches: (PersonCreditJob) -> Bool
    ) -> (group: Group, consumed: Set<String>)? {
        var selected: [PersonCredit] = []
        var consumed = Set<String>()
        for credit in credits {
            let jobs = credit.jobs.filter(matches)
            guard !jobs.isEmpty else { continue }
            for job in jobs {
                consumed.insert(consumedKey(creditID: credit.id, job: job.job))
            }
            selected.append(credit.keepingJobs(jobs))
        }
        guard !selected.isEmpty else { return nil }
        return (Group(department: department, title: title, credits: selected), consumed)
    }

    private static func leftoverCrew(_ credits: [PersonCredit], consumed: Set<String>) -> Group? {
        var selected: [PersonCredit] = []
        for credit in credits {
            let jobs = credit.jobs.filter {
                !consumed.contains(consumedKey(creditID: credit.id, job: $0.job))
            }
            guard !jobs.isEmpty else { continue }
            selected.append(credit.keepingJobs(jobs))
        }
        guard !selected.isEmpty else { return nil }
        return Group(department: .crew, title: "Crew", credits: selected)
    }

    private static func consumedKey(creditID: String, job: String) -> String {
        "\(creditID)|\(job)"
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
            creditSections: creditSections,
            awards: awards,
            fullscreenImages: fullscreenImages ?? self.fullscreenImages
        )
    }

    func withFullscreen(_ fullscreen: FullscreenImages?) -> PersonDetailContent {
        copy(fullscreenImages: .some(fullscreen))
    }
}
