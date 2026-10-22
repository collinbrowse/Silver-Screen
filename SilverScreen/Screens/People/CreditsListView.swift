//
//  CreditsListView.swift
//  SilverScreen
//

import SwiftUI

struct CreditsListView: View {
    @State private var viewModel: CreditsListViewModel
    let imageLoader: ImageLoader
    var router: NavigationRouter?


    init(
        personID: Int,
        personName: String,
        department: CreditDepartment,
        people: PersonRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter? = nil
    ) {
        _viewModel = State(
            initialValue: CreditsListViewModel(
                personID: personID,
                personName: personName,
                department: department,
                people: people
            )
        )
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView()
                case .empty:
                    EmptyStateView(
                        title: "No Credits",
                        message: "No credits were found for this section.",
                        systemImage: "film"
                    )
                case .loaded(let content, _):
                    list(content.items)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.retry()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    /// One credit per row on a phone; two or three side by side on wider screens.
    private func list(_ items: [CreditsListItem]) -> some View {
        CatalogColumnsReader { columns in
            List {
                Section {
                    ForEach(CatalogGrid.rows(items, columns: columns, id: \.id)) { gridRow in
                        CatalogColumnsRow(row: gridRow, columns: columns, id: \.id) { item in
                            creditRow(item)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparatorBetweenCells(isFirst: gridRow.isFirst, isLast: gridRow.isLast)
                    }
                }
                .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: true)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func creditRow(_ item: CreditsListItem) -> some View {
        let row = CreditsListRow(item: item, imageLoader: imageLoader)
        if let router {
            Button {
                switch item.credit.mediaType {
                    case .movie:
                        router.push(.movieDetail(id: item.credit.mediaID))
                    case .tv:
                        router.push(.tvSeries(id: item.credit.mediaID))
                }
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            row
        }
    }
}
