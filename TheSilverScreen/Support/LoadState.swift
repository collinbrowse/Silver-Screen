//
//  LoadState.swift
//  TheSilverScreen
//

import Foundation

enum LoadActivity: Sendable, Equatable {
    case none
    case refreshing
    case loadingMore
    case failed(AppError)
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
