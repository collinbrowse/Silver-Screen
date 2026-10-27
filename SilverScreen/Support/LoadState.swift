//
//  LoadState.swift
//  SilverScreen
//

import Foundation

enum LoadActivity: Sendable, Equatable {
    case none
    case refreshing
    case loadingMore
    case failed(AppError)

    /// True when no refresh or page is in flight. A soft failure does not block the next
    /// page, so scrolling back to the end after a failed page or list save tries again.
    var allowsLoadMore: Bool {
        switch self {
            case .none, .failed: true
            case .refreshing, .loadingMore: false
        }
    }
}

enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case empty
    case loaded(Value, activity: LoadActivity)
    case failed(AppError)

    static func loaded(_ value: Value) -> Self {
        .loaded(value, activity: .none)
    }
}

extension LoadState: Equatable where Value: Equatable {}
