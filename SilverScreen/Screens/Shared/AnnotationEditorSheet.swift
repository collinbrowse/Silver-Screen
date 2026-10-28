//
//  AnnotationEditorSheet.swift
//  SilverScreen
//
//  Combined rating and note editor. A new rating must be chosen before Save.
//  X discards the draft. Delete clears rating and note together. A failed save
//  stays on this sheet. Cancelled writes do not show a persistence banner. The
//  view model owns dismissal after success. The note field fills leftover height
//  above the keyboard as the sheet resizes. Focus is resigned before any dismiss
//  so the keyboard and sheet do not fight. Every save outcome goes to the
//  review prompter, which decides whether this is a good moment to ask.
//

import SwiftUI
import UIKit

struct AnnotationEditorSheet: View {
    let title: String
    let canClear: Bool
    let onSave: (Double, String) async -> AnnotationEditorWriteResult
    let onClear: () async -> AnnotationEditorWriteResult

    @Environment(\.dismiss) private var dismiss
    /// Nil in previews and anywhere the root did not install one.
    @Environment(ReviewPrompter.self) private var reviewPrompter: ReviewPrompter?
    /// Committed rating for Save. Nil until the title already had one or the slider moves.
    @State private var score: Double?
    @State private var note: String
    @State private var confirmClear = false
    /// The sheet's safe-area insets, read so the side margins can be balanced.
    @State private var safeAreaInsets = EdgeInsets()
    @State private var saveError: AppError?
    @State private var isSaving = false
    @FocusState private var noteFocused: Bool

    init(
        title: String,
        score: Double?,
        note: String,
        canClear: Bool,
        onSave: @escaping (Double, String) async -> AnnotationEditorWriteResult,
        onClear: @escaping () async -> AnnotationEditorWriteResult
    ) {
        self.title = title
        self.canClear = canClear
        self.onSave = onSave
        self.onClear = onClear
        _score = State(initialValue: score.map(UserScore.snapped))
        _note = State(initialValue: note)
    }

    /// Side margin that honors only the inset both edges share. The iPhone Duo's
    /// outer screen has a sensor strip on one side, so its sheet's safe area is much
    /// deeper on that edge; following it left a wide empty gutter beside the slider
    /// and note while the toolbar's X sat in that space. A symmetric inset (iPhone
    /// landscape) keeps the margin it had.
    private var horizontalMargin: CGFloat {
        DesignSpacing.lg + min(safeAreaInsets.leading, safeAreaInsets.trailing)
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

                ScoreSlider(score: $score, isDisabled: isSaving) {
                    if noteFocused {
                        resignNoteFocus()
                    }
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                        .fill(DesignTheme.surface)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isSaving else { return }
                            noteFocused = true
                        }

                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .font(DesignTypography.body)
                        .lineLimit(3...)
                        .focused($noteFocused)
                        .disabled(isSaving)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, DesignSpacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .accessibilityLabel("Note")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // In the sheet, not the toolbar: a third toolbar button wraps onto a second
                // row on the iPhone Duo's outer screen, over the rating.
                if canClear {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Delete Rating and Review", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }
            }
            .padding(.vertical, DesignSpacing.lg)
            .padding(.horizontal, horizontalMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DesignTheme.canvas)
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                proxy.safeAreaInsets
            } action: { insets in
                safeAreaInsets = insets
            }
            .ignoresSafeArea(.container, edges: .horizontal)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        Task { await dismissEditor() }
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
                    .disabled(!canSave)
                }
            }
            .alert("Delete your rating and review?", isPresented: $confirmClear) {
                Button("Delete", role: .destructive) {
                    guard !isSaving else { return }
                    isSaving = true
                    Task { await clearAnnotation() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your rating and note for this title.")
            }
        }
        .presentationDetents([.medium, .large])
        // Swiping away while the note is focused makes the keyboard and sheet
        // animations fight (and trips UIKit prediction-bar constraints). Require
        // the keyboard to drop first; Cancel/Save resign focus before dismiss.
        .interactiveDismissDisabled(isSaving || noteFocused)
    }

    private func save() async {
        guard let score else {
            isSaving = false
            return
        }
        await resignNoteFocusBeforeLeaving()
        let result = await onSave(score, note)
        finish(result)
        await reviewPrompter?.ratingSaveFinished(result)
    }

    private func clearAnnotation() async {
        await resignNoteFocusBeforeLeaving()
        finish(await onClear())
    }

    private func dismissEditor() async {
        await resignNoteFocusBeforeLeaving()
        dismiss()
    }

    private func finish(_ result: AnnotationEditorWriteResult) {
        switch result {
            case .succeeded:
                saveError = nil
                // Keep isSaving true while the view model clears the sheet item so
                // unlocking controls cannot bounce layout mid-dismiss.
            case .cancelled:
                isSaving = false
                saveError = nil
            case .failed:
                isSaving = false
                saveError = .persistence
        }
    }

    /// Drops keyboard focus before the sheet animates away. Matches Search’s
    /// resign-first pattern so the prediction bar is not laid out at zero width.
    private func resignNoteFocusBeforeLeaving() async {
        resignNoteFocus()
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func resignNoteFocus() {
        noteFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
