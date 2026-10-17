//
//  LogWatchButton.swift
//  SilverScreen
//
//  "Log a watch" card for a detail screen, with the title's watch count and last day.
//  Reads `DiaryContext` from the environment and draws nothing where the root did not
//  install one (previews), so a detail screen needs no new initializer arguments.
//

import SwiftUI

struct LogWatchButton: View {
    let title: LogWatchTitle
    /// The title's own rating, prefilled into a new entry.
    let currentScore: Double?

    @Environment(DiaryContext.self) private var context: DiaryContext?

    var body: some View {
        if let context {
            LogWatchCard(
                title: title,
                currentScore: currentScore,
                context: context
            )
            .id(title.subject)
        }
    }
}

/// The card itself, which owns its view model once the context is known.
private struct LogWatchCard: View {
    let currentScore: Double?
    @State private var viewModel: LogWatchViewModel

    init(title: LogWatchTitle, currentScore: Double?, context: DiaryContext) {
        self.currentScore = currentScore
        _viewModel = State(initialValue: LogWatchViewModel(title: title, context: context))
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
            viewModel.beginLog(currentScore: currentScore)
        } label: {
            SurfaceCard {
                HStack(spacing: DesignSpacing.md) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                        Text(viewModel.actionTitle)
                            .font(DesignTypography.section)
                            .foregroundStyle(DesignTheme.textPrimary)
                        if let summary = viewModel.summary {
                            Text(summary)
                                .font(DesignTypography.metadata)
                                .foregroundStyle(DesignTheme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DesignTheme.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Adds this watch to your diary")
        .sheet(item: editorBinding) { session in
            DiaryEntryEditorSheet(
                session: session,
                onSave: { await viewModel.save($0) },
                onDelete: { .cancelled }
            )
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.contextRevision) { _, _ in
            Task { await viewModel.load() }
        }
    }
}
