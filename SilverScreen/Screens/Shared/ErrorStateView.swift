//
//  ErrorStateView.swift
//  SilverScreen
//

import SwiftUI

/// Full-screen failure for a load with nothing to show. When the failure was the network
/// and a retry is offered, it also retries by itself as soon as `NetworkMonitor` reports
/// the device is back online.
struct ErrorStateView: View {
    let error: AppError
    let retry: (() async -> Void)?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

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
            if retriesOnReconnect {
                Text("We'll try again when you're back online.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if error.isRetryable, let retry {
                Button("Retry") {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centered text and Retry would sit on the iPhone Duo's crease; keep them in one pane.
        .foldPane()
        .accessibilityElement(children: .combine)
        .onChange(of: network?.reconnections) { _, _ in
            guard retriesOnReconnect, let retry else { return }
            Task { await retry() }
        }
    }

    /// Network failures with a retry recover on their own once the connection returns.
    private var retriesOnReconnect: Bool {
        retry != nil && error.retriesOnReconnect
    }
}
