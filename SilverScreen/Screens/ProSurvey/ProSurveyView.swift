//
//  ProSurveyView.swift
//  SilverScreen
//
//  "Pro is coming soon. What features would you like to see?" Pushed from
//  Settings, or shown in a sheet from the Library card; it never owns a
//  NavigationStack, so it works in both.
//

import SwiftUI

struct ProSurveyView: View {
    @State private var viewModel: ProSurveyViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ProSurveyViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .sent:
                    EmptyStateView(
                        title: "Thanks for Your Picks",
                        message: "They'll decide what Silver Screen Pro includes. You can change them here anytime.",
                        systemImage: "checkmark.seal",
                        actionTitle: "Done"
                    ) {
                        dismiss()
                    }
                case .composing, .sending, .failed:
                    form
            }
        }
        .navigationTitle("Silver Screen Pro")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.appeared() }
    }

    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("Pro is coming soon")
                        .font(.title2.bold())
                        .foregroundStyle(DesignTheme.textPrimary)
                    Text("What features would you like to see? Pick as many as you like.")
                        .font(.body)
                        .foregroundStyle(DesignTheme.textSecondary)
                }
                .padding(.vertical, DesignSpacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }

            Section {
                ForEach(viewModel.options) { feature in
                    ProSurveyFeatureRow(feature: feature, isSelected: viewModel.isSelected(feature)) {
                        viewModel.toggle(feature)
                    }
                }
            }

            Section {
                TextField("Anything else? (optional)", text: $viewModel.other, axis: .vertical)
                    .lineLimit(2...6)
            } footer: {
                Text("Your picks go to the developer with your app version, never your name, library, or ratings.")
            }

            if case .failed(let error) = viewModel.state {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            Text("Your picks weren't sent")
                                .font(.headline)
                            Text(error.title)
                                .font(.subheadline)
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.state == .sending {
                    ProgressView()
                        .accessibilityLabel("Sending")
                } else {
                    Button(viewModel.isEditingEarlierAnswers ? "Update" : "Send") {
                        Task { await viewModel.submit() }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
        }
    }
}
