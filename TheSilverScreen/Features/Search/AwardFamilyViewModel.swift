//
//  AwardFamilyViewModel.swift
//  TheSilverScreen
//
//  Categories present in the catalog for one prize body. A new category shows
//  up here without an app change.
//

import Foundation

@Observable
@MainActor
final class AwardFamilyViewModel {
    let family: AwardFamily
    private(set) var state: LoadState<[AwardCategory]> = .idle

    private let awards: AwardsRepository

    init(family: AwardFamily, awards: AwardsRepository) {
        self.family = family
        self.awards = awards
    }

    var navigationTitle: String { family.title }

    func load() async {
        guard case .idle = state else { return }
        state = .loading
        let categories = await awards.categories(in: family)
        state = categories.isEmpty ? .empty : .loaded(categories)
    }
}

