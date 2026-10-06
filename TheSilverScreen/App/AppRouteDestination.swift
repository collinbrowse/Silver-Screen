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
                    awards: awards,
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
            case .tvSeason(let seriesID, let seriesName, let seasonNumber, let seriesSnapshot):
                TVSeasonRouteView(
                    seriesID: seriesID,
                    seriesName: seriesName,
                    seasonNumber: seasonNumber,
                    seriesSnapshot: seriesSnapshot,
                    shows: shows,
                    lists: lists,
                    listsIndex: listsIndex,
                    annotations: annotations,
                    awards: awards,
                    imageLoader: imageLoader,
                    router: router
                )
            case .tvEpisode(let seriesID, let seriesName, let seasonNumber, let episodeNumber, let seriesSnapshot):
                TVEpisodeRouteView(
                    seriesID: seriesID,
                    seriesName: seriesName,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    seriesSnapshot: seriesSnapshot,
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
            case .genreBrowse(let genre):
                GenreBrowseView(
                    genre: genre,
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
