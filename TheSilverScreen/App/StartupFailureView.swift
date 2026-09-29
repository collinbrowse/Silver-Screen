//
//  StartupFailureView.swift
//  TheSilverScreen
//

import SwiftUI

struct StartupFailureView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(.label))
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}

