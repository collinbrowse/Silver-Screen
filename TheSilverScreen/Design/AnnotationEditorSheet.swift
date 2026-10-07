//
//  AnnotationEditorSheet.swift
//  TheSilverScreen
//
//  Combined rating and note editor. X discards the draft. Trash confirms note
//  deletion. A failed save stays on this sheet.
//

import SwiftUI

struct AnnotationEditorSheet: View {
    let canDeleteNote: Bool
    let onSave: (Double, String) async -> Bool
    let onDeleteNote: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var score: Double
    @State private var note: String
    @State private var confirmDelete = false
    @State private var saveError: AppError?
    @State private var isSaving = false

    init(
        score: Double,
        note: String,
        canDeleteNote: Bool,
        onSave: @escaping (Double, String) async -> Bool,
        onDeleteNote: @escaping () async -> Bool
    ) {
        self.canDeleteNote = canDeleteNote
        self.onSave = onSave
        self.onDeleteNote = onDeleteNote
        _score = State(initialValue: Self.snapped(score))
        _note = State(initialValue: note)
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
                    Text(UserScore.formatted(score))
                        .font(DesignTypography.ratingValue)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .accessibilityLabel(UserScore.accessibilityLabel(score))

                    Slider(
                        value: $score,
                        in: 0.5...10,
                        step: 0.5
                    )
                    .tint(DesignTheme.accent)
                    .accessibilityLabel("Your rating")
                    .accessibilityValue(UserScore.formatted(score))
                }

                TextField("Note (optional)", text: $note, axis: .vertical)
                    .font(DesignTypography.body)
                    .lineLimit(3...8)
                    .padding(DesignSpacing.sm)
                    .background(DesignTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
                    .accessibilityLabel("Note")
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
                    .accessibilityLabel("Cancel")
                }
                if canDeleteNote {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete note")
                    }
                    ToolbarSpacer(.fixed, placement: .confirmationAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Delete this note?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task { await deleteNote() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your note for this title. Your rating stays.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        let saved = await onSave(Self.snapped(score), note)
        isSaving = false
        if saved {
            saveError = nil
            dismiss()
        } else {
            saveError = .persistence
        }
    }

    private func deleteNote() async {
        isSaving = true
        let deleted = await onDeleteNote()
        isSaving = false
        if deleted {
            saveError = nil
            dismiss()
        } else {
            saveError = .persistence
        }
    }

    private static func snapped(_ value: Double) -> Double {
        let steps = (value * 2).rounded()
        let clamped = min(max(steps, 1), 20)
        return clamped / 2.0
    }
}
