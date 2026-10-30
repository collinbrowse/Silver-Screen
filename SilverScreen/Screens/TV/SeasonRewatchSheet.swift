//
//  SeasonRewatchSheet.swift
//  SilverScreen
//
//  Log a Rewatch on a watched season: pick the day, and every episode gets a rewatch
//  on it. Rating happens per episode, or on the season as a verdict. A failed save keeps
//  the sheet open.
//

import SwiftUI

struct SeasonRewatchSheet: View {
    let title: String
    let onSave: (Date, Bool) async -> AnnotationEditorWriteResult

    @Environment(\.dismiss) private var dismiss
    @State private var watchedOn = Date()
    @State private var dontRemember = false
    @State private var isSaving = false
    @State private var saveError: AppError?

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Text("\(saveError.title): \(saveError.message)")
                            .font(DesignTypography.chip)
                            .foregroundStyle(Color.red)
                            .accessibilityLabel("\(saveError.title). \(saveError.message)")
                    }
                }
                Section {
                    if !dontRemember {
                        DatePicker(
                            "Watched on",
                            selection: $watchedOn,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }
                    Toggle("Don't remember", isOn: $dontRemember)
                        .tint(DesignTheme.accent)
                } footer: {
                    Text("Adds a rewatch of every episode in this season.")
                }
            }
            .disabled(isSaving)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isSaving)
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSaving)
    }

    private func save() async {
        switch await onSave(watchedOn, !dontRemember) {
            case .succeeded:
                dismiss()
            case .cancelled:
                isSaving = false
            case .failed:
                isSaving = false
                saveError = .persistence
        }
    }
}
