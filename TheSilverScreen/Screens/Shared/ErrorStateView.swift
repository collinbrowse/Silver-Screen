//
//  ErrorStateView.swift
//  TheSilverScreen
//

import SwiftUI

struct ErrorStateView: View {
    let error: AppError
    let retry: (() async -> Void)?

    init(error: AppError, retry: (() async -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(error.title)
                .font(.title2)
                .multilineTextAlignment(.center)
            Text(error.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if error.isRetryable, let retry {
                Button("Retry") {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
