//
//  AnnotationEditorSheet.swift
//  TheSilverScreen
//
//  Combined rating and note editor. A new rating must be chosen before Save.
//  X discards the draft. Trash clears rating and note together. A failed save
//  stays on this sheet. Cancelled writes do not show a persistence banner. The
//  view model owns dismissal after success. The note field fills leftover height
//  above the keyboard as the sheet resizes. Focus is resigned before any dismiss
//  so the keyboard and sheet do not fight.
//

import SwiftUI
import UIKit

struct AnnotationEditorSheet: View {
    let title: String
    let canClear: Bool
    let onSave: (Double, String) async -> AnnotationEditorWriteResult
    let onClear: () async -> AnnotationEditorWriteResult

    @Environment(\.dismiss) private var dismiss
    /// Committed rating for Save. Nil until the title already had one or the slider moves.
    @State private var score: Double?
    /// Slider thumb position; does not imply a chosen score until `score` is set.
    @State private var sliderValue: Double
    @State private var note: String
    @State private var confirmClear = false
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
                    HStack(alignment: .firstTextBaseline) {
                        Text("Rate out of 10")
                            .font(DesignTypography.metadata)
                            .foregroundStyle(DesignTheme.textSecondary)
                        Spacer(minLength: DesignSpacing.sm)
                        if let score {
                            Text(UserScore.formatted(score))
                                .font(DesignTypography.ratingValue)
                                .foregroundStyle(DesignTheme.accent)
                                .accessibilityLabel(UserScore.accessibilityLabel(score))
                        } else {
                            Text("-")
                                .font(DesignTypography.ratingValue)
                                .foregroundStyle(DesignTheme.accent)
                                .accessibilityLabel("Choose a rating")
                        }
                    }

                    Slider(
                        value: Binding(
                            get: { sliderValue },
                            set: { newValue in
                                sliderValue = newValue
                                score = Self.snapped(newValue)
                                if noteFocused {
                                    resignNoteFocus()
                                }
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
            }
            .padding(DesignSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DesignTheme.canvas)
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
                if canClear {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            confirmClear = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.red)
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Delete rating and review")
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
        finish(await onSave(score, note))
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

    private static func snapped(_ value: Double) -> Double {
        let steps = (value * 2).rounded()
        let clamped = min(max(steps, 1), 20)
        return clamped / 2.0
    }
}
