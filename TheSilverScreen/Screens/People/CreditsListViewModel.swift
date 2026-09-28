//
//  CreditsListViewModel.swift
//  TheSilverScreen
//

import Foundation

struct CreditsListItem: Sendable, Equatable, Identifiable {
    let credit: PersonCredit
    let genreNames: [String]
    let formattedReleaseDate: String

    var id: String { credit.id }
}

struct CreditsListContent: Sendable, Equatable {
    let personName: String
    let department: CreditDepartment
    let items: [CreditsListItem]
}

@Observable
@MainActor
final class CreditsListViewModel {
    private(set) var state: LoadState<CreditsListContent> = .idle

    private let personID: Int
    private let personName: String
    private let department: CreditDepartment
    private let people: PersonRepository

    init(
        personID: Int,
        personName: String,
        department: CreditDepartment,
        people: PersonRepository
    ) {
        self.personID = personID
        self.personName = personName
        self.department = department
        self.people = people
    }

    var navigationTitle: String {
        switch department {
        case .cast: return "Acting Roles"
        case .crew: return "Crew Roles"
        }
    }

    func load() async {
        state = .loading

        do {
            let detail = try await people.personDetail(id: personID)
            let credits: [PersonCredit]
            switch department {
            case .cast: credits = detail.castCredits
            case .crew: credits = detail.crewCredits
            }
            let items = credits.map { credit in
                CreditsListItem(
                    credit: credit,
                    genreNames: PersonDetailViewModel.genreNames(for: credit),
                    formattedReleaseDate: PersonDetailViewModel.formatReleaseDate(credit.releaseDate)
                )
            }
            if items.isEmpty {
                state = .empty
            } else {
                state = .loaded(
                    CreditsListContent(
                        personName: personName,
                        department: department,
                        items: items
                    )
                )
            }
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
}
