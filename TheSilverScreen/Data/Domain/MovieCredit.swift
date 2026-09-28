//
//  MovieCredit.swift
//  TheSilverScreen
//

import Foundation

struct CastMember: Sendable, Identifiable, Equatable, Hashable {
    /// TMDB credit_id — unique per casting even when the same person plays two roles.
    let id: String
    let personID: Int
    let name: String
    let character: String
    let profilePath: String?
    let order: Int
    /// Person-scoped department from TMDB (e.g. "Acting"); used when favoriting.
    let knownForDepartment: String?

    init(
        id: String,
        personID: Int,
        name: String,
        character: String,
        profilePath: String?,
        order: Int,
        knownForDepartment: String? = nil
    ) {
        self.id = id
        self.personID = personID
        self.name = name
        self.character = character
        self.profilePath = profilePath
        self.order = order
        self.knownForDepartment = knownForDepartment
    }
}

struct CrewMember: Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let personID: Int
    let name: String
    let job: String
    let department: String
    let profilePath: String?
    /// Person-scoped department from TMDB (e.g. "Directing"); used when favoriting.
    let knownForDepartment: String?

    init(
        id: String,
        personID: Int,
        name: String,
        job: String,
        department: String,
        profilePath: String?,
        knownForDepartment: String? = nil
    ) {
        self.id = id
        self.personID = personID
        self.name = name
        self.job = job
        self.department = department
        self.profilePath = profilePath
        self.knownForDepartment = knownForDepartment
    }
}

/// A person shown in a crew carousel after Director / Writing-department filtering and dedupe.
struct CreditedPerson: Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let roles: [String]
    let profilePath: String?
    /// Person-scoped department from TMDB; used when favoriting.
    let knownForDepartment: String?

    init(
        id: Int,
        name: String,
        roles: [String],
        profilePath: String?,
        knownForDepartment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.roles = roles
        self.profilePath = profilePath
        self.knownForDepartment = knownForDepartment
    }

    var rolesLabel: String {
        roles.joined(separator: ", ")
    }
}
