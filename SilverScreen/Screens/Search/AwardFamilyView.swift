//
//  AwardFamilyView.swift
//  SilverScreen
//

import SwiftUI

struct AwardFamilyView: View {
    @State private var viewModel: AwardFamilyViewModel
    var router: NavigationRouter?


    init(family: AwardFamily, awards: AwardsRepository, router: NavigationRouter?) {
        _viewModel = State(initialValue: AwardFamilyViewModel(family: family, awards: awards))
        self.router = router
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    EmptyStateView(
                        title: "No Categories",
                        message: "This award has no titles in the catalog yet.",
                        systemImage: "trophy"
                    )
                case .loaded(let categories, _):
                    list(categories)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.load()
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

    /// One category per row on a phone, two or three side by side on a wide screen.
    private func list(_ categories: [AwardCategory]) -> some View {
        CatalogColumnsReader { columns in
            List {
                Section {
                    ForEach(CatalogGrid.rows(categories, columns: columns, id: \.id)) { row in
                        CatalogColumnsRow(row: row, columns: columns, id: \.id) { category in
                            categoryButton(category)
                        }
                        .listRowSeparatorBetweenCells(isFirst: row.isFirst, isLast: row.isLast)
                    }
                }
                .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: true)
            }
            .listStyle(.plain)
        }
    }

    private func categoryButton(_ category: AwardCategory) -> some View {
        Button {
            router?.push(
                .awardTitles(
                    AwardTitleRequest(family: viewModel.family, category: category.name)
                )
            )
        } label: {
            HStack {
                Text(category.name)
                    .font(DesignTypography.body)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(DesignTypography.chip.weight(.semibold))
                    .foregroundStyle(DesignTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityHint("Shows winners and nominees")
    }
}
