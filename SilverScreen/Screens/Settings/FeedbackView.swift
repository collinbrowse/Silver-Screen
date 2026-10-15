//
//  FeedbackView.swift
//  SilverScreen
//

import SwiftUI

struct FeedbackView: View {
    @State private var viewModel: FeedbackViewModel
    @FocusState private var messageFocused: Bool

    init(viewModel: FeedbackViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .composing:
                    form
                case .sent:
                    EmptyStateView(
                        title: "Thanks for the Feedback",
                        message: "It went straight to the developer.",
                        systemImage: "checkmark.bubble"
                    )
                case .unavailable:
                    EmptyStateView(
                        title: "Couldn't Send",
                        message: "This build can't send feedback. Help & Support in Settings has another way to reach the developer.",
                        systemImage: "exclamationmark.bubble"
                    )
            }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        Form {
            Section {
                TextField("What's working, what isn't, what you'd add", text: $viewModel.message, axis: .vertical)
                    .lineLimit(6...12)
                    .focused($messageFocused)
            } footer: {
                Text("Your app version is included.")
            }

            Section {
                TextField("Email (optional)", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text(viewModel.emailIsValid ? "Only if you'd like a reply." : "Enter a full email address, or leave it blank.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") { viewModel.submit() }
                    .disabled(!viewModel.canSubmit)
            }
        }
        .onAppear { messageFocused = true }
    }
}
