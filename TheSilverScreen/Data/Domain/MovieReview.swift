//
//  MovieReview.swift
//  TheSilverScreen
//

import Foundation

struct MovieReview: Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let author: String
    let username: String
    let content: String
    let updatedAt: Date?
}

struct MovieReviewPage: Sendable, Equatable {
    let reviews: [MovieReview]
    let page: Int
    let hasMore: Bool
    /// Every review TMDB reports, including ones not loaded yet.
    let totalCount: Int
}
