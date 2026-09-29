//
//  NoteEditorSheet.swift
//  TheSilverScreen
//
//  Note editor. X discards the draft. Trash confirms deletion. A failed save stays on this sheet.
//

import SwiftUI

struct NoteEditorSheet: View {
    let canDelete: Bool
    let onSave: (String) async -> Bool
    let onDelete: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var confirmDelete = false
    @State private var saveError: AppError?
    @State private var isSaving = false

    init(
        draft: String,
        canDelete: Bool,
        onSave: @escaping (String) async -> Bool,
        onDelete: @escaping () async -> Bool
    ) {
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                if let saveError {
                    Text("\(saveError.title): \(saveError.message)")
                        .font(DesignTypography.chip)
                        .foregroundStyle(.white)
                        .padding(DesignSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red)
                        .accessibilityLabel("\(saveError.title). \(saveError.message)")
                }
                TextEditor(text: $draft)
                    .font(DesignTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(DesignSpacing.sm)
                    .background(DesignTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            }
            .padding(DesignSpacing.lg)
            .background(DesignTheme.canvas)
            .navigationTitle("Note")
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
                if canDelete {
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
                    Task { await delete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your note for this title.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        let saved = await onSave(draft)
        isSaving = false
        if saved {
            saveError = nil
            dismiss()
        } else {
            saveError = .persistence
        }
    }

    private func delete() async {
        isSaving = true
        let deleted = await onDelete()
        isSaving = false
        if deleted {
            saveError = nil
            dismiss()
        } else {
            saveError = .persistence
        }
    }
}
