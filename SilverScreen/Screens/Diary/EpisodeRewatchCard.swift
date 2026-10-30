//
//  EpisodeRewatchCard.swift
//  SilverScreen
//
//  The Log a Rewatch button on a watched episode's page. Reads `DiaryContext` from the
//  environment and draws nothing without one (previews), so the episode screen needs no
//  new initializer arguments.
//

import SwiftUI

struct EpisodeRewatchCard: View {
    let title: LogWatchTitle

    @Environment(DiaryContext.self) private var context: DiaryContext?

    var body: some View {
        if let context {
            EpisodeRewatchButton(title: title, context: context)
                .id(title.subject)
        }
    }
}

/// The button itself, which owns its view model once the diary is known.
private struct EpisodeRewatchButton: View {
    @State private var viewModel: EpisodeRewatchViewModel

    init(title: LogWatchTitle, context: DiaryContext) {
        _viewModel = State(initialValue: EpisodeRewatchViewModel(title: title, context: context))
    }

    private var editorBinding: Binding<DiaryEditorSession?> {
        Binding(
            get: { viewModel.editor },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissEditor()
                }
            }
        )
    }

    var body: some View {
        Button {
            viewModel.begin()
        } label: {
            Label("Log a Rewatch", systemImage: "arrow.counterclockwise")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.accentOnFill)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTheme.accent)
        .controlSize(.large)
        .accessibilityHint("Adds a new watch of this episode to your diary, dated today")
        .sheet(item: editorBinding) { session in
            DiaryEntryEditorSheet(
                session: session,
                onSave: { await viewModel.save($0) },
                onDelete: { .cancelled }
            )
        }
    }
}
