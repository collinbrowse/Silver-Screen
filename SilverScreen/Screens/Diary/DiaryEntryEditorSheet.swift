//
//  DiaryEntryEditorSheet.swift
//  SilverScreen
//
//  Editor for one watch: the day (never in the future), an optional rating and review
//  for that viewing, a rewatch switch, and tags. Save keeps the sheet open on failure.
//  Editing an existing entry also offers Delete, behind a confirmation. Sized as a form
//  sheet so it reads the same on iPhone and iPad.
//

import SwiftUI

struct DiaryEntryEditorSheet: View {
    let session: DiaryEditorSession
    let onSave: (DiaryEntryDraft) async -> AnnotationEditorWriteResult
    let onDelete: () async -> AnnotationEditorWriteResult

    @Environment(\.dismiss) private var dismiss
    @State private var draft: DiaryEntryDraft
    @State private var isSaving = false
    @State private var saveError: AppError?
    @State private var confirmDelete = false

    init(
        session: DiaryEditorSession,
        onSave: @escaping (DiaryEntryDraft) async -> AnnotationEditorWriteResult,
        onDelete: @escaping () async -> AnnotationEditorWriteResult
    ) {
        self.session = session
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: session.draft)
    }

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
                    DatePicker(
                        "Watched on",
                        selection: $draft.watchedOn,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    Toggle("Rewatch", isOn: $draft.isRewatch)
                }

                Section {
                    Picker("Rating", selection: $draft.score) {
                        Text("No rating").tag(Double?.none)
                        ForEach(UserScore.options, id: \.self) { option in
                            Text(UserScore.formatted(option)).tag(Double?.some(option))
                        }
                    }
                    .accessibilityValue(draft.score.map(UserScore.formatted) ?? "No rating")
                } footer: {
                    Text("This rating is for this watch. Your rating for the title stays as it is.")
                }

                Section("Review") {
                    TextField("What did you think? (optional)", text: $draft.review, axis: .vertical)
                        .lineLimit(4...)
                        .accessibilityLabel("Review")
                }

                Section {
                    TextField("Tags, separated by commas", text: $draft.tagsText)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Tags")
                }

                if session.canDelete {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            confirmDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(session.title)
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
                        Task { finish(await onSave(draft)) }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Delete this entry?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    guard !isSaving else { return }
                    isSaving = true
                    Task { finish(await onDelete()) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes this watch from your diary. Your rating for the title is not changed.")
            }
        }
        .presentationSizing(.form)
        .interactiveDismissDisabled(isSaving)
    }

    private func finish(_ result: AnnotationEditorWriteResult) {
        switch result {
            case .succeeded:
                // The view model clears the session, which dismisses the sheet.
                saveError = nil
            case .cancelled:
                isSaving = false
                saveError = nil
            case .failed:
                isSaving = false
                saveError = .persistence
        }
    }
}
