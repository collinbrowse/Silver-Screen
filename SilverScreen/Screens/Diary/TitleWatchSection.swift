//
//  TitleWatchSection.swift
//  SilverScreen
//
//  The rating card and, once there is a watch, Log a Rewatch. Hosts the Log sheet they
//  open, so movie and episode pages share one path. Without a view model (still loading,
//  or previews) it shows only the TMDB score.
//

import SwiftUI

struct TitleWatchSection: View {
    let viewModel: TitleWatchViewModel?
    let formattedRating: String
    let ratingAccessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            TMDBRatingCard(
                formattedRating: formattedRating,
                accessibilityLabel: ratingAccessibilityLabel,
                formattedUserScore: viewModel?.formattedUserScore,
                userScoreAccessibilityLabel: viewModel?.scoreAccessibilityLabel ?? "",
                userScoreCaption: viewModel?.scoreCaption,
                showsUserSide: viewModel?.isWatched == true,
                onEdit: { viewModel?.openRating() }
            )
            if let viewModel, viewModel.isWatched {
                LogRewatchButton { viewModel.beginRewatch() }
                    .sheet(item: editorBinding(for: viewModel)) { session in
                        DiaryEntryEditorSheet(
                            session: session,
                            onSave: { await viewModel.save($0) },
                            onDelete: { await viewModel.deleteOpenWatch() }
                        )
                    }
            }
        }
    }

    private func editorBinding(for viewModel: TitleWatchViewModel) -> Binding<DiaryEditorSession?> {
        Binding(
            get: { viewModel.editor },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissEditor()
                }
            }
        )
    }
}
