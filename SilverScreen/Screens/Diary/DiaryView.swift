//
//  DiaryView.swift
//  SilverScreen
//
//  Every logged watch and TV episode check-off, grouped by month, newest first. Tapping
//  a logged watch edits it; swipe or the context menu deletes it or opens the title.
//  An episodes row opens its show, where episodes are marked and unmarked. A movie's own
//  history pins a Log a Rewatch button above the list. The column is centered at a
//  readable width when the screen is wide (see `DiaryLayout`).
//

import SwiftUI

struct DiaryView: View {
    @State var viewModel: DiaryViewModel
    let imageLoader: ImageLoader
    let router: NavigationRouter

    @State private var availableWidth: CGFloat = 0
    /// The watch being shared as an image; drives the share sheet.
    @State private var shareCard: ShareCardContent?

    private var layout: DiaryLayout { DiaryLayout(width: availableWidth) }

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
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView()
                case .empty:
                    if viewModel.scope == nil {
                        EmptyStateView(
                            title: "No Diary Entries",
                            message: "Mark a movie or an episode watched with its eye, and it shows up here by the day you watched it.",
                            systemImage: "book.closed"
                        )
                    } else {
                        EmptyStateView(
                            title: "No Watches Yet",
                            message: "Watches you log for this title show up here.",
                            systemImage: "book.closed"
                        )
                    }
                case .loaded(let months, let activity):
                    list(months)
                        .overlay(alignment: .top) {
                            LoadActivityBanner(activity: activity)
                        }
                case .failed(let error):
                    ErrorStateView(error: error) {
                        await viewModel.load()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pinned above the list (and its empty state) so it is the first thing on a
        // movie's history, rather than a row that scrolls away.
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.canLogRewatch {
                logRewatchButton
            }
        }
        .background(DesignTheme.canvas)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
        .navigationTitle(viewModel.navigationTitle)
        // Inline when the column is centered on a wide screen: a large title stays at the
        // leading edge and no longer lines up with the rows.
        .toolbarTitleDisplayMode(
            viewModel.prefersInlineTitle || layout.horizontalMargin > 0 ? .inline : .inlineLarge
        )
        .sheet(item: $shareCard) { card in
            ShareCardSheet(content: card, imageLoader: imageLoader)
        }
        .sheet(item: editorBinding) { session in
            DiaryEntryEditorSheet(
                session: session,
                onSave: { await viewModel.save($0) },
                onDelete: { await viewModel.deleteEditorEntry() }
            )
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.contextRevision) { _, _ in
            Task { await viewModel.load() }
        }
    }

    /// Opens the sheet for a new watch dated today.
    private var logRewatchButton: some View {
        LogRewatchButton {
            Task { await viewModel.beginRewatch() }
        }
    }

    private func list(_ months: [DiaryMonth]) -> some View {
        List {
            ForEach(months) { month in
                Section {
                    ForEach(month.items) { item in
                        switch item {
                            case .entry(let row):
                                entryRow(row, layout: layout)
                            case .episodes(let group):
                                if viewModel.showsTitleLinks {
                                    Button {
                                        router.push(viewModel.route(for: group))
                                    } label: {
                                        DiaryEpisodeGroupRow(group: group, layout: layout, imageLoader: imageLoader)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens the show")
                                    .contextMenu {
                                        Button("Go to Show", systemImage: "tv") {
                                            router.push(viewModel.route(for: group))
                                        }
                                    }
                                } else {
                                    DiaryEpisodeGroupRow(
                                        group: group,
                                        layout: layout,
                                        imageLoader: imageLoader,
                                        showsTitle: viewModel.showsRowTitles,
                                        leadingPoster: viewModel.showsSeasonPosters
                                            ? DiaryLeadingPoster(path: viewModel.historyPoster(for: group))
                                            : nil
                                    )
                                }
                        }
                    }
                } header: {
                    Text(month.title)
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            if !viewModel.earlierRows.isEmpty {
                Section {
                    ForEach(viewModel.earlierRows) { row in
                        entryRow(row, layout: layout)
                    }
                } header: {
                    Text("Earlier")
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, layout.horizontalMargin, for: .scrollContent)
    }

    /// A watch's row: tap to edit, with delete and, on the full diary, a link to the title.
    @ViewBuilder
    private func entryRow(_ row: DiaryRow, layout: DiaryLayout) -> some View {
        Button {
            viewModel.edit(row)
        } label: {
            DiaryEntryRow(
                row: row,
                layout: layout,
                imageLoader: imageLoader,
                showsTitle: viewModel.showsRowTitles,
                leadingPoster: viewModel.showsSeasonPosters
                    ? DiaryLeadingPoster(path: viewModel.historyPoster(for: row))
                    : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits this entry")
        .accessibilityAction(named: "Delete") {
            Task { await viewModel.delete(row) }
        }
        .accessibilityActions {
            if viewModel.showsTitleLinks {
                Button("Open title") {
                    router.push(viewModel.route(for: row))
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.delete(row) }
            }
        }
        .accessibilityAction(named: "Share") {
            shareCard = .watch(row.entry)
        }
        .contextMenu {
            Button("Edit Entry", systemImage: "pencil") {
                viewModel.edit(row)
            }
            Button("Share…", systemImage: "square.and.arrow.up") {
                shareCard = .watch(row.entry)
            }
            if viewModel.showsTitleLinks {
                Button(
                    row.entry.subject.kind == .tv ? "Go to Show" : "Go to Movie",
                    systemImage: row.entry.subject.kind == .tv ? "tv" : "film"
                ) {
                    router.push(viewModel.route(for: row))
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await viewModel.delete(row) }
            }
        }
    }
}
