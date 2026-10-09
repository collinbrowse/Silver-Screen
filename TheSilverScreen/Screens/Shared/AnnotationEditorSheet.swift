//
//  AnnotationEditorSheet.swift
//  TheSilverScreen
//
//  Combined rating and note editor. A new rating must be chosen before Save.
//  X discards the draft. Trash confirms note deletion. Remove rating clears
//  score and note. A failed save stays on this sheet. Cancelled writes do not
//  show a persistence banner. The view model owns dismissal after success.
//

import SwiftUI

struct AnnotationEditorSheet: View {
    let canDeleteNote: Bool
    let hasExistingScore: Bool
    let canClear: Bool
    let onSave: (Double, String) async -> AnnotationEditorWriteResult
    let onDeleteNote: () async -> AnnotationEditorWriteResult
    let onClear: () async -> AnnotationEditorWriteResult

    @Environment(\.dismiss) private var dismiss
    /// Committed rating for Save. Nil until the title already had one or the slider moves.
    @State private var score: Double?
    /// Slider thumb position; does not imply a chosen score until `score` is set.
    @State private var sliderValue: Double
    @State private var note: String
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var saveError: AppError?
    @State private var isSaving = false

    init(
        score: Double?,
        note: String,
        canDeleteNote: Bool,
        hasExistingScore: Bool,
        canClear: Bool,
        onSave: @escaping (Double, String) async -> AnnotationEditorWriteResult,
        onDeleteNote: @escaping () async -> AnnotationEditorWriteResult,
        onClear: @escaping () async -> AnnotationEditorWriteResult
    ) {
        self.canDeleteNote = canDeleteNote
        self.hasExistingScore = hasExistingScore
        self.canClear = canClear
        self.onSave = onSave
        self.onDeleteNote = onDeleteNote
        self.onClear = onClear
        let initial = score.map(Self.snapped)
        _score = State(initialValue: initial)
        _sliderValue = State(initialValue: initial ?? 5.5)
        _note = State(initialValue: note)
    }

    private var canSave: Bool {
        score != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                if let saveError {
                    Text("\(saveError.title): \(saveError.message)")
                        .font(DesignTypography.chip)
                        .foregroundStyle(.white)
                        .padding(DesignSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red)
                        .accessibilityLabel("\(saveError.title). \(saveError.message)")
                }

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    if let score {
                        Text(UserScore.formatted(score))
                            .font(DesignTypography.ratingValue)
                            .foregroundStyle(DesignTheme.textPrimary)
                            .accessibilityLabel(UserScore.accessibilityLabel(score))
                    } else {
                        Text("-")
                            .font(DesignTypography.ratingValue)
                            .foregroundStyle(DesignTheme.textSecondary)
                            .accessibilityLabel("Choose a rating")
                    }

                    Slider(
                        value: Binding(
                            get: { sliderValue },
                            set: { newValue in
                                sliderValue = newValue
                                score = Self.snapped(newValue)
                            }
                        ),
                        in: 0.5...10,
                        step: 0.5
                    )
                    .tint(DesignTheme.accent)
                    .disabled(isSaving)
                    .accessibilityLabel("Your rating")
                    .accessibilityValue(
                        score.map(UserScore.formatted) ?? "No rating chosen"
                    )
                }

                TextField("Note (optional)", text: $note, axis: .vertical)
                    .font(DesignTypography.body)
                    .lineLimit(3...8)
                    .padding(DesignSpacing.sm)
                    .background(DesignTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
                    .disabled(isSaving)
                    .accessibilityLabel("Note")

                if canClear {
                    Button("Remove rating", role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(isSaving)
                    .accessibilityLabel(clearAccessibilityLabel)
                }
            }
            .padding(DesignSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DesignTheme.canvas)
            .navigationTitle("Your rating")
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
                if canDeleteNote {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Delete note")
                    }
                    ToolbarSpacer(.fixed, placement: .confirmationAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("Delete this note?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    guard !isSaving else { return }
                    isSaving = true
                    Task { await deleteNote() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .alert(clearAlertTitle, isPresented: $confirmClear) {
                Button("Remove", role: .destructive) {
                    guard !isSaving else { return }
                    isSaving = true
                    Task { await clearAnnotation() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(clearMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSaving)
    }

    private var deleteMessage: String {
        if hasExistingScore {
            return "This removes your note for this title. Your rating stays."
        }
        return "This removes your note for this title."
    }

    private var clearAlertTitle: String {
        hasExistingScore ? "Remove your rating?" : "Remove this note?"
    }

    private var clearMessage: String {
        if hasExistingScore {
            return "This removes your rating and note for this title."
        }
        return "This removes your note for this title."
    }

    private var clearAccessibilityLabel: String {
        hasExistingScore ? "Remove rating" : "Remove note"
    }

    private func save() async {
        guard let score else {
            isSaving = false
            return
        }
        finish(await onSave(score, note))
    }

    private func deleteNote() async {
        finish(await onDeleteNote())
    }

    private func clearAnnotation() async {
        finish(await onClear())
    }

    private func finish(_ result: AnnotationEditorWriteResult) {
        isSaving = false
        switch result {
            case .succeeded, .cancelled:
                saveError = nil
            case .failed:
                saveError = .persistence
        }
    }

    private static func snapped(_ value: Double) -> Double {
        let steps = (value * 2).rounded()
        let clamped = min(max(steps, 1), 20)
        return clamped / 2.0
    }
}
