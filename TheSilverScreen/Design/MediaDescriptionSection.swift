//
//  MediaDescriptionSection.swift
//  TheSilverScreen
//
//  TMDB overview and the viewer's note for one title. A saved note is the page
//  that shows first. An arrow beside Storyline opens the overview.
//  An arrow beside Your notes, kept on the right, returns.
//

import SwiftUI

struct MediaDescriptionSection: View {
    let overview: String
    let note: String?
    /// Day the note was last saved.
    var notedOn: String? = nil
    let onSave: (String) async -> Bool
    let onDelete: () async -> Bool

    @State private var page: Page
    /// True when the storyline is arriving from the right. Notes arrive from the left.
    @State private var storylineFromTrailing = true
    @State private var editor: EditorSession?

    init(
        overview: String,
        note: String?,
        notedOn: String? = nil,
        onSave: @escaping (String) async -> Bool,
        onDelete: @escaping () async -> Bool
    ) {
        self.overview = overview
        self.note = note
        self.notedOn = notedOn
        self.onSave = onSave
        self.onDelete = onDelete
        _page = State(initialValue: note == nil ? .description : .notes)
    }

    private enum Page {
        case notes
        case description
    }

    private struct EditorSession: Identifiable {
        let id = UUID()
        let draft: String
        let canDelete: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            header
            textBlock
            if page == .notes, let notedOn {
                Text(notedOn)
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
                    .accessibilityLabel("Note saved \(notedOn)")
            }
        }
        .clipped()
        .onAppear(perform: resetPage)
        .onChange(of: note) { _, _ in
            resetPage()
        }
        .sheet(item: $editor) { session in
            NoteEditorSheet(
                draft: session.draft,
                canDelete: session.canDelete,
                onSave: onSave,
                onDelete: onDelete
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSpacing.sm) {
            if note == nil {
                sectionTitle("Storyline")
                Spacer(minLength: 0)
                Button(action: add) {
                    Label("Add note", systemImage: "plus")
                        .font(DesignTypography.metadata.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Add note")
            } else if page == .notes {
                editTitle
                Spacer(minLength: 0)
                pageSwitch(title: "Storyline", arrow: "arrow.right", arrowFirst: false, label: "Show storyline") {
                    showStoryline()
                }
            } else {
                sectionTitle("Storyline")
                Spacer(minLength: 0)
                pageSwitch(title: "Your notes", arrow: "arrow.left", arrowFirst: true, label: "Show your notes") {
                    showNotes()
                }
            }
        }
    }

    /// Two points smaller than the section headline, and still scaled with Dynamic Type.
    private var labelFont: Font { .subheadline.weight(.semibold) }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(labelFont)
            .foregroundStyle(DesignTheme.textPrimary)
    }

    /// "Your notes" and the pencil are one control, including the space between them.
    private var editTitle: some View {
        Button(action: edit) {
            HStack(spacing: DesignSpacing.sm) {
                Text("Your notes")
                    .font(labelFont)
                    .foregroundStyle(DesignTheme.textPrimary)
                Image(systemName: "pencil")
                    .font(labelFont)
                    .foregroundStyle(DesignTheme.textPrimary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Edit note")
    }

    private func pageSwitch(
        title: String,
        arrow: String,
        arrowFirst: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSpacing.xs) {
                if arrowFirst {
                    Image(systemName: arrow)
                        .accessibilityHidden(true)
                }
                Text(title)
                if !arrowFirst {
                    Image(systemName: arrow)
                        .accessibilityHidden(true)
                }
            }
            .font(labelFont)
            .foregroundStyle(DesignTheme.accent)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var textBlock: some View {
        Text(visibleText)
            .font(DesignTypography.body)
            .foregroundStyle(DesignTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .id(page)
            .transition(textTransition)
            .accessibilityLabel(page == .notes && note != nil ? "Your notes. \(visibleText)" : "Storyline. \(visibleText)")
    }

    /// Storyline slides in from the right. Notes slide in from the left.
    private var textTransition: AnyTransition {
        let edge: Edge = storylineFromTrailing ? .trailing : .leading
        let exit: Edge = storylineFromTrailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: exit).combined(with: .opacity)
        )
    }

    private func showStoryline() {
        storylineFromTrailing = true
        withAnimation(.smooth(duration: 0.35)) {
            page = .description
        }
    }

    private func showNotes() {
        storylineFromTrailing = false
        withAnimation(.smooth(duration: 0.35)) {
            page = .notes
        }
    }

    private var visibleText: String {
        if page == .notes, let note {
            return note
        }
        return overview.isEmpty ? "No description available." : overview
    }

    private func resetPage() {
        page = note == nil ? .description : .notes
    }

    private func add() {
        editor = EditorSession(draft: "", canDelete: false)
    }

    private func edit() {
        editor = EditorSession(draft: note ?? "", canDelete: note != nil)
    }
}

/// Note editor. X discards the draft. Trash confirms deletion. A failed save stays on this sheet.
private struct NoteEditorSheet: View {
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
