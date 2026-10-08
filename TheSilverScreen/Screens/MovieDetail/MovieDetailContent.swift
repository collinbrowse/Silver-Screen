//
//  MovieDetailContent.swift
//  TheSilverScreen
//

import Foundation

struct MovieDetailContent: Sendable, Equatable {
    struct ImagesSection: Sendable, Equatable {
        let items: [MovieImage]
    }

    struct CastSection: Sendable, Equatable {
        let members: [CastMember]
    }

    struct CrewSection: Sendable, Equatable {
        let people: [CreditedPerson]
    }

    struct SimilarSection: Sendable, Equatable {
        struct Item: Sendable, Equatable, Identifiable {
            let movie: Movie
            let genreNames: [String]
            let formattedReleaseDate: String

            var id: Int { movie.id }
        }

        let items: [Item]
    }

    struct CollectionSection: Sendable, Equatable {
        let id: Int
        let title: String
        let posterPath: String?
        let movies: [Movie]
    }

    struct ReviewsSection: Sendable, Equatable {
        let items: [MovieReview]
        let nextPage: Int
        let hasMore: Bool
        let totalCount: Int
        let isLoadingPage: Bool
        let pageError: AppError?
    }

    let detail: MovieDetail
    let formattedRating: String
    let ratingAccessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let userNote: String?
    let formattedRatedOn: String?
    let formattedNotedOn: String?
    let formattedBudget: String
    let budgetAccessibilityLabel: String
    let formattedRevenue: String
    let revenueAccessibilityLabel: String
    let formattedReleaseDate: String
    /// Year · runtime · leading genres under the title. Empty when every part is missing.
    let heroMetadataLine: String
    let heroMetadataAccessibilityLabel: String
    let images: ImagesSection?
    let cast: CastSection?
    let crew: CrewSection?
    let similar: SimilarSection?
    let collection: CollectionSection?
    let reviews: ReviewsSection?

    /// Non-nil while the image lightbox is open (presentation state owned by the VM so
    /// UIKit-hosted detail can present reliably).
    var fullscreenImages: FullscreenImages?
}

struct FullscreenImages: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        case poster
        case backdrop
        case profile
    }

    var id: String { initialID }
    let initialID: String
    let images: [MovieImage]
    let kind: Kind

    init(
        initialID: String,
        images: [MovieImage],
        kind: Kind = .backdrop
    ) {
        self.initialID = initialID
        self.images = images
        self.kind = kind
    }
}
