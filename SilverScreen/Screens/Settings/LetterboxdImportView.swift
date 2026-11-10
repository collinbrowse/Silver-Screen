//
//  LetterboxdImportView.swift
//  SilverScreen
//
//  Settings → Import from Letterboxd. Explains how to get the export, opens the file
//  picker, then shows matching progress, a confirm step, and a summary.
//

import SwiftUI
import UniformTypeIdentifiers

struct LetterboxdImportView: View {
    @State var viewModel: LetterboxdImportViewModel
    @State private var isPicking = false

    var body: some View {
        List {
            switch viewModel.phase {
                case .choosing:
                    instructions
                case .nothingFound:
                    instructions
                    Section {
                        Label(
                            "Those files had no diary, ratings, watched, or watchlist. Pick diary.csv, ratings.csv, watched.csv, and watchlist.csv, or the whole unzipped export folder.",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                case .matching(let done, let total):
                    progressSection(title: "Finding your films", done: done, total: total)
                case .review(let review):
                    reviewSections(review)
                case .importing(let done, let total):
                    progressSection(title: "Adding to your library", done: done, total: total)
                case .finished(let summary):
                    summarySections(summary)
                case .failed(let error):
                    Section {
                        Label(error.title, systemImage: "exclamationmark.triangle")
                        Text(error.message)
                            .foregroundStyle(DesignTheme.textSecondary)
                        Button("Start Over") { viewModel.reset() }
                    }
            }
        }
        .navigationTitle("Import from Letterboxd")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: [.commaSeparatedText, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await viewModel.load(urls: urls) }
        }
    }

    private var instructions: some View {
        Section {
            Text("Bring your Letterboxd diary, ratings, reviews, and watchlist into Silver Screen. Watch dates and rewatches come with them.")
            Text("1. On letterboxd.com, open Settings → Data → Export Your Data.\n2. Open the ZIP in Files to unzip it.\n3. Choose the unzipped folder, or its CSV files.")
                .foregroundStyle(DesignTheme.textSecondary)
            Button("Choose Export…", systemImage: "folder") { isPicking = true }
        } footer: {
            Text("Films are matched to TMDB by title and year. Nothing already in your library is changed, so importing again is safe.")
        }
    }

    private func progressSection(title: String, done: Int, total: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(title)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("\(done) of \(total) films")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            Text("Keep Silver Screen open until this finishes.")
        }
    }

    @ViewBuilder
    private func reviewSections(_ review: LetterboxdImportReview) -> some View {
        Section("Ready to Import") {
            LabeledContent("Films", value: "\(review.matchedFilms)")
            LabeledContent("Watches", value: "\(review.watches)")
            LabeledContent("Ratings", value: "\(review.ratings)")
            LabeledContent("Reviews", value: "\(review.reviews)")
            LabeledContent("Watchlist", value: "\(review.watchlist)")
            Button("Import", systemImage: "square.and.arrow.down") {
                Task { await viewModel.confirm() }
            }
            .disabled(review.matchedFilms == 0)
        }
        unmatchedSection(review.unmatched)
        Section {
            Button("Cancel", role: .cancel) { viewModel.reset() }
        }
    }

    @ViewBuilder
    private func summarySections(_ summary: LetterboxdImportSummary) -> some View {
        Section("Imported") {
            LabeledContent("Films logged", value: "\(summary.filmsLogged)")
            LabeledContent("Watches added", value: "\(summary.watchesAdded)")
            LabeledContent("Added to Watchlist", value: "\(summary.watchlistAdded)")
            if summary.alreadyInLibrary > 0 {
                LabeledContent("Already in your library", value: "\(summary.alreadyInLibrary)")
            }
            if summary.failed > 0 {
                LabeledContent("Couldn't save", value: "\(summary.failed)")
            }
        }
        unmatchedSection(summary.unmatched)
        Section {
            Button("Import Another Export") { viewModel.reset() }
        }
    }

    @ViewBuilder
    private func unmatchedSection(_ films: [LetterboxdFilm]) -> some View {
        if !films.isEmpty {
            Section {
                ForEach(Array(films.enumerated()), id: \.offset) { _, film in
                    Text(film.year.map { "\(film.name) (\($0))" } ?? film.name)
                }
            } header: {
                Text("Not Found on TMDB (\(films.count))")
            } footer: {
                Text("These weren't imported. Add them from Search.")
            }
        }
    }
}
