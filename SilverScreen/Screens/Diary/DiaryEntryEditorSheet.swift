//
//  DiaryEntryEditorSheet.swift
//  SilverScreen
//
//  Editor for one watch: the day (never in the future), an optional rating (the same
//  slider as the Rate sheet) and review for that viewing. Whether it is a
//  rewatch comes from the title's history, so there is no switch for it. Save keeps the sheet open on failure.
//  Editing an existing entry also offers Delete, behind a confirmation. Sized as a form
//  sheet so it reads the same on iPhone and iPad.
//

import SwiftUI

struct DiaryEntryEditorSheet: View {
    let session: DiaryEditorSession
    let onSave: (DiaryEntryDraft) async -> AnnotationEditorWriteResult
    let onDelete: () async -> AnnotationEditorWriteResult

    @Environment(\.dismiss) private var dismiss
    /// Nil in previews and anywhere the root did not install one.
    @Environment(ReviewPrompter.self) private var reviewPrompter: ReviewPrompter?
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

    private var dontRemember: Binding<Bool> {
        Binding(
            get: { !draft.isDateKnown },
            set: { draft.isDateKnown = !$0 }
        )
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
                    if draft.isDateKnown {
                        DatePicker(
                            "Watched on",
                            selection: $draft.watchedOn,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }
                    Toggle("Don't remember", isOn: dontRemember)
                        .tint(DesignTheme.accent)
                }

                Section {
                    ScoreSlider(score: $draft.score, isDisabled: isSaving)
                    if draft.score != nil {
                        Button("Clear Rating") {
                            draft.score = nil
                        }
                        .tint(DesignTheme.accent)
                        .disabled(isSaving)
                    }
                } footer: {
                    Text("Your rating for this title is the one from your newest rated watch.")
                }

                Section("Review") {
                    TextField("What did you think? (optional)", text: $draft.review, axis: .vertical)
                        .lineLimit(4...)
                        .accessibilityLabel("Review")
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
                        Task { await save() }
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
                Text("This removes this watch from your diary, with its rating and review.")
            }
        }
        .presentationSizing(.form)
        .interactiveDismissDisabled(isSaving)
    }

    /// A saved rating goes to the review prompter, which decides whether this is a good
    /// moment to ask. A watch saved without a rating is not a rating moment.
    private func save() async {
        let result = await onSave(draft)
        finish(result)
        if draft.score != nil {
            await reviewPrompter?.ratingSaveFinished(result)
        }
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
