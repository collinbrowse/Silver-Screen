//
//  AppRouteDestination.swift
//  TheSilverScreen
//

import SwiftUI

struct AppRouteDestination: View {
    let route: Route
    let movies: MovieRepository
    let shows: TVRepository
    let people: PersonRepository
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let annotations: AnnotationsRepository
    let awards: AwardsRepository
    let imageLoader: ImageLoader
    let router: NavigationRouter

    var body: some View {
        switch route {
        case .movieDetail(let id):
            MovieDetailRouteView(
                movieID: id,
                movies: movies,
                lists: lists,
                listsIndex: listsIndex,
                annotations: annotations,
                awards: awards,
                imageLoader: imageLoader,
                router: router
            )
        case .person(let id):
            PersonDetailRouteView(
                personID: id,
                people: people,
                lists: lists,
                listsIndex: listsIndex,
                imageLoader: imageLoader,
                router: router
            )
        case .personCredits(let personID, let personName, let department):
            CreditsListView(
                personID: personID,
                personName: personName,
                department: department,
                people: people,
                imageLoader: imageLoader,
                router: router
            )
        case .collection(let id):
            CollectionRouteView(
                collectionID: id,
                movies: movies,
                lists: lists,
                listsIndex: listsIndex,
                annotations: annotations,
                imageLoader: imageLoader,
                router: router
            )
        case .tvSeries(let id):
            TVSeriesRouteView(
                seriesID: id,
                shows: shows,
                lists: lists,
                listsIndex: listsIndex,
                annotations: annotations,
                awards: awards,
                imageLoader: imageLoader,
                router: router
            )
        case .tvSeason(let seriesID, let seriesName, let seasonNumber):
            TVSeasonRouteView(
                seriesID: seriesID,
                seriesName: seriesName,
                seasonNumber: seasonNumber,
                shows: shows,
                lists: lists,
                listsIndex: listsIndex,
                annotations: annotations,
                awards: awards,
                imageLoader: imageLoader,
                router: router
            )
        case .tvEpisode(let seriesID, let seriesName, let seasonNumber, let episodeNumber):
            TVEpisodeRouteView(
                seriesID: seriesID,
                seriesName: seriesName,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                shows: shows,
                lists: lists,
                listsIndex: listsIndex,
                annotations: annotations,
                awards: awards,
                imageLoader: imageLoader,
                router: router
            )
        case .libraryList(let id):
            LibraryDetailRouteView(
                listID: id,
                lists: lists,
                annotations: annotations,
                imageLoader: imageLoader,
                router: router
            )
        case .awardFamily(let family):
            AwardFamilyView(family: family, awards: awards, router: router)
        case .awardTitles(let request):
            AwardTitlesView(
                request: request,
                awards: awards,
                movies: movies,
                shows: shows,
                annotations: annotations,
                lists: lists,
                listsIndex: listsIndex,
                imageLoader: imageLoader,
                router: router
            )
        }
    }
}

struct MovieDetailRouteView: View {
    @State private var viewModel: MovieDetailViewModel
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let imageLoader: ImageLoader
    let router: NavigationRouter

    init(
        movieID: Int,
        movies: MovieRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: MovieDetailViewModel(
                movieID: movieID,
                movies: movies,
                annotations: annotations,
                awards: awards
            )
        )
        self.lists = lists
        self.listsIndex = listsIndex
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        MovieDetailView(
            viewModel: viewModel,
            lists: lists,
            listsIndex: listsIndex,
            imageLoader: imageLoader,
            router: router
        )
    }
}

struct PersonDetailRouteView: View {
    @State private var viewModel: PersonDetailViewModel
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let imageLoader: ImageLoader
    let router: NavigationRouter

    init(
        personID: Int,
        people: PersonRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: PersonDetailViewModel(
                personID: personID,
                people: people
            )
        )
        self.lists = lists
        self.listsIndex = listsIndex
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        PersonDetailView(
            viewModel: viewModel,
            lists: lists,
            listsIndex: listsIndex,
            imageLoader: imageLoader,
            router: router
        )
    }
}

struct CollectionRouteView: View {
    @State private var viewModel: CollectionViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let router: NavigationRouter

    init(
        collectionID: Int,
        movies: MovieRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: CollectionViewModel(
                collectionID: collectionID,
                movies: movies,
                annotations: annotations
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.router = router
    }

    var body: some View {
        CollectionView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            router: router
        )
    }
}

struct TVSeriesRouteView: View {
    @State private var viewModel: TVSeriesViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let router: NavigationRouter

    init(
        seriesID: Int,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVSeriesViewModel(
                seriesID: seriesID,
                shows: shows,
                annotations: annotations,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.router = router
    }

    var body: some View {
        TVSeriesView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            router: router
        )
    }
}

struct TVSeasonRouteView: View {
    @State private var viewModel: TVSeasonViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let router: NavigationRouter
    let seriesID: Int
    let seasonNumber: Int

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVSeasonViewModel(
                seriesID: seriesID,
                seriesName: seriesName,
                seasonNumber: seasonNumber,
                shows: shows,
                annotations: annotations,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.router = router
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
    }

    var body: some View {
        TVSeasonView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            router: router,
            seriesID: seriesID,
            seasonNumber: seasonNumber
        )
    }
}

struct TVEpisodeRouteView: View {
    @State private var viewModel: TVEpisodeViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let seriesID: Int
    let seriesName: String
    let seasonNumber: Int
    let router: NavigationRouter

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        episodeNumber: Int,
        shows: TVRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        annotations: AnnotationsRepository,
        awards: AwardsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: TVEpisodeViewModel(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                shows: shows,
                annotations: annotations,
                awards: awards
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.router = router
    }

    var body: some View {
        TVEpisodeView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            lists: lists,
            listsIndex: listsIndex,
            seriesID: seriesID,
            seriesName: seriesName,
            seasonNumber: seasonNumber,
            router: router
        )
    }
}

struct LibraryDetailRouteView: View {
    @State private var viewModel: LibraryDetailViewModel
    let lists: ListsRepository
    let imageLoader: ImageLoader
    let router: NavigationRouter

    init(
        listID: UUID,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter
    ) {
        _viewModel = State(
            initialValue: LibraryDetailViewModel(
                listID: listID,
                lists: lists,
                annotations: annotations
            )
        )
        self.lists = lists
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        LibraryDetailView(
            viewModel: viewModel,
            imageLoader: imageLoader,
            router: router,
            lists: lists
        )
    }
}
