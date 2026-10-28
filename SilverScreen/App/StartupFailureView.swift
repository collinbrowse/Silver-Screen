//
//  StartupFailureView.swift
//  SilverScreen
//

import SwiftUI

/// Shown when the dependency graph cannot be built at launch. Try Again rebuilds it, which
/// recovers from a transient cause such as a database file still locked before first unlock.
struct StartupFailureView: View {
    let message: String
    let retry: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.label))
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    /// The text for `error`: an `AppError`'s own title and message, otherwise a generic line.
    static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return "\(appError.title)\n\n\(appError.message)"
        }
        return "The app could not start."
    }

    /// Error domain and code only. A description can carry a file path with the device's
    /// user name, which must not reach Sentry.
    static func errorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
