//
//  PersonDetailView.swift
//  TheSilverScreen
//

import SwiftUI

struct PersonDetailView: View {
    @Bindable var viewModel: PersonDetailViewModel
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let imageLoader: ImageLoader
    var router: NavigationRouter?
    var showsToolbarFavorite: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    private let profileCardWidth: CGFloat = 140
    private let imageCardWidth: CGFloat = 180
    private let portraitCardWidth: CGFloat = 140

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    EmptyStateView(
                    title: "Person Unavailable",
                    message: "This person could not be found.",
                    systemImage: "person"
                    )
                case .loaded(let content, let activity):
                    loadedBody(content: content, activity: activity)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.retry()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .toolbar {
            if showsToolbarFavorite, case .loaded(let content, _) = viewModel.state {
                ToolbarItem(placement: .topBarTrailing) {
                    ListMembershipButton(
                        draft: content.detail.listItem(),
                        lists: lists,
                        index: listsIndex
                    ) {
                        viewModel.noteListSaveFailed()
                    }
                }
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
        .fullScreenCover(item: showsToolbarFavorite ? fullscreenBinding : .constant(nil)) { fullscreen in
            FullscreenImageViewer(
                images: fullscreen.images,
                initialID: fullscreen.initialID,
                imageKind: fullscreen.kind,
                imageLoader: imageLoader
            ) {
                viewModel.dismissImages()
            }
        }
    }

    private var navigationTitle: String {
        if case .loaded(let content, _) = viewModel.state {
            return content.detail.name
        }
        return ""
    }

    private var fullscreenBinding: Binding<FullscreenImages?> {
        Binding(
            get: {
                if case .loaded(let content, _) = viewModel.state {
                    return content.fullscreenImages
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissImages()
                }
            }
        )
    }

    private func loadedBody(content: PersonDetailContent, activity: LoadActivity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                metadataBlock(content)
                if let images = content.images {
                    imagesCarousel(images)
                }
                ForEach(content.creditSections) { section in
                    creditsCarousel(
                        title: section.title,
                        section: section,
                        personID: content.detail.id,
                        personName: content.detail.name
                    )
                }
            }
            .padding(.vertical, DesignSpacing.lg)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .coordinateSpace(.named("detailScroll"))
        }
        .scrollingInlineTitle(navigationTitle)
        .overlay(alignment: .top) {
            if case .failed(let error) = activity {
                Text("\(error.title): \(error.message)")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .accessibilityLabel("\(error.title). \(error.message)")
            }
        }
    }

    private func metadataBlock(_ content: PersonDetailContent) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xl) {
            header(content)
            biographySection(content.detail.biography)
            if hasFacts(content) {
                factsCard(content)
            }
            if !content.awards.isEmpty {
                AwardRowsSection(rows: content.awards.map(\.row)) { route in
                    router?.push(route)
                }
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    private func header(_ content: PersonDetailContent) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    profileThumbnail(path: content.detail.profilePath, width: profileCardWidth)
                    nameAndIMDb(content)
                }
            } else {
                HStack(alignment: .top, spacing: DesignSpacing.md) {
                    profileThumbnail(path: content.detail.profilePath, width: profileCardWidth)
                    nameAndIMDb(content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func nameAndIMDb(_ content: PersonDetailContent) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text(content.detail.name)
                .font(DesignTypography.title)
                .foregroundStyle(DesignTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .inlineTitleAnchor()
                .accessibilityAddTraits(.isHeader)
            if let imdbID = content.detail.imdbID {
                imdbButton(imdbID: imdbID)
            }
        }
    }

    @ViewBuilder
    private func profileThumbnail(path: String?, width: CGFloat) -> some View {
        let image = RemoteImageView(
            path: path,
            kind: .profile,
            width: width,
            aspectRatio: 2 / 3,
            imageLoader: imageLoader,
            placeholderSystemImage: "person.fill"
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous))
        .frame(width: width, height: width * 3 / 2)

        if path != nil {
            image
                .contentShape(RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous))
                .onTapGesture {
                    viewModel.openProfile()
                }
                .accessibilityLabel("Profile photo")
                .accessibilityHint("Shows the profile photo full screen")
                .accessibilityAddTraits(.isButton)
        } else {
            image
        }
    }

    private func imdbButton(imdbID: String) -> some View {
        Button {
            guard let url = URL(string: "https://www.imdb.com/name/\(imdbID)/") else { return }
            openURL(url)
        } label: {
            HStack(spacing: DesignSpacing.sm) {
                Image("IMDb")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                Image(systemName: "arrow.up.right.square")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open IMDb page in Safari")
        .accessibilityAddTraits(.isLink)
    }

    private func biographySection(_ biography: String) -> some View {
        BiographySection(biography: biography)
    }

    private func hasFacts(_ content: PersonDetailContent) -> Bool {
        content.formattedBirthday != nil
            || content.formattedDeathday != nil
            || content.placeOfBirth != nil
    }

    private func factsCard(_ content: PersonDetailContent) -> some View {
        let rows = factRows(content)
        return SurfaceCard {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        factCell(label: row.label, value: row.value)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, DesignSpacing.md)
                        }
                        factCell(label: row.label, value: row.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private struct FactRow {
        let label: String
        let value: String
    }

    private func factRows(_ content: PersonDetailContent) -> [FactRow] {
        var rows: [FactRow] = []
        if let birthday = content.formattedBirthday {
            rows.append(FactRow(label: "Birthday", value: birthday))
        }
        if let deathday = content.formattedDeathday {
            rows.append(FactRow(label: "Died", value: deathday))
        }
        if let place = content.placeOfBirth {
            rows.append(FactRow(label: "Place of Birth", value: place))
        }
        return rows
    }

    private func factCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(label.uppercased())
                .font(DesignTypography.factLabel)
                .foregroundStyle(DesignTheme.textMuted)
                .tracking(0.6)
            Text(value)
                .font(DesignTypography.factValue)
                .foregroundStyle(DesignTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func imagesCarousel(_ section: PersonDetailContent.ImagesSection) -> some View {
        DetailCarousel(title: "Images") {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, image in
                RemoteImageView(
                    path: image.filePath,
                    kind: .profile,
                    width: imageCardWidth,
                    aspectRatio: 2 / 3,
                    imageLoader: imageLoader,
                    placeholderSystemImage: "person.fill"
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.carousel, style: .continuous))
                .frame(width: imageCardWidth, height: imageCardWidth * 3 / 2)
                .contentShape(RoundedRectangle(cornerRadius: DesignRadius.carousel, style: .continuous))
                .onTapGesture {
                    viewModel.openImages(initialID: image.id)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Image \(index + 1) of \(section.items.count)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    viewModel.openImages(initialID: image.id)
                }
            }
        }
        .padding(.bottom, DesignSpacing.xl)
    }

    private func creditsCarousel(
        title: String,
        section: PersonDetailContent.CreditsSection,
        personID: Int,
        personName: String
    ) -> some View {
        DetailCarousel(
            title: title,
            viewAllTitle: section.showsViewAll ? "View All" : nil,
            onViewAll: section.showsViewAll
                ? {
                    router?.push(
                        .personCredits(
                            personID: personID,
                            personName: personName,
                            department: section.department
                        )
                    )
                }
                : nil
        ) {
            ForEach(section.preview) { credit in
                creditCell(credit)
            }
        }
    }

    private func creditCell(_ credit: PersonCredit) -> some View {
        let navigable = router != nil
        return VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            RemoteImageView(
                path: credit.posterPath,
                kind: .poster,
                width: portraitCardWidth,
                aspectRatio: 2 / 3,
                imageLoader: imageLoader,
                placeholderSystemImage: credit.mediaType == .tv ? "tv" : "film"
            )
            .carouselCard(width: portraitCardWidth, aspectRatio: 2 / 3)
            .overlay(alignment: .topTrailing) {
                creditListControl(credit)
                    .padding(DesignSpacing.xs)
            }

            Text(credit.title)
                .font(DesignTypography.metadata.weight(.semibold))
                .foregroundStyle(DesignTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(creditAccessibilityLabel(credit))
                .accessibilityAddTraits(navigable ? .isButton : [])
        }
        .frame(width: portraitCardWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            switch credit.mediaType {
                case .movie:
                    router?.push(.movieDetail(id: credit.mediaID))
                case .tv:
                    router?.push(.tvSeries(id: credit.mediaID))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func creditListControl(_ credit: PersonCredit) -> some View {
        ListMembershipButton(draft: credit.listItem(), lists: lists, index: listsIndex) {
            viewModel.noteListSaveFailed()
        }
    }

    private func creditAccessibilityLabel(_ credit: PersonCredit) -> String {
        var parts = [credit.title]
        switch credit.mediaType {
            case .movie: parts.append("Movie")
            case .tv: parts.append("TV series")
        }
        if !credit.roleLabel.isEmpty {
            parts.append(credit.roleLabel)
        }
        return parts.joined(separator: ", ")
    }
}

/// Collapsed biography that expands in place via Show More / Show Less.
private struct BiographySection: View {
    let biography: String

    @State private var expanded = false

    private let previewLineLimit = 10
    /// Rough threshold where ~10 body lines are typically exceeded.
    private let expandsWhenCharacterCountExceeds = 500

    private var displayText: String {
        biography.isEmpty ? "No biography available." : biography
    }

    private var canExpand: Bool {
        !biography.isEmpty && biography.count > expandsWhenCharacterCountExceeds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("Biography")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(displayText)
                .font(DesignTypography.body)
                .foregroundStyle(DesignTheme.textSecondary)
                .lineLimit(canExpand && !expanded ? previewLineLimit : nil)
                .fixedSize(horizontal: false, vertical: true)

            if canExpand {
                Button(expanded ? "Show Less" : "Show More") {
                    expanded.toggle()
                }
                .font(DesignTypography.chip.weight(.semibold))
                .foregroundStyle(DesignTheme.accent)
                .frame(minHeight: 44)
                .accessibilityHint(
                    expanded ? "Collapses the biography" : "Expands the full biography"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

