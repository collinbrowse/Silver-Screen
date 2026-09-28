//
//  AwardTitlesViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class AwardTitlesViewModelTests: XCTestCase {

    func test_categoryQuery_pagesLocalCredits() async {
        let awards = AwardsRepository(catalog: Self.pagedCatalog)
        let viewModel = AwardTitlesViewModel(
            request: AwardTitleRequest(family: .academy, category: "Best Picture"),
            awards: awards,
            movies: MovieRepository.test(client: FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet)))),
            shows: TVRepository.test(client: FakeHTTPClient(result: .failure(URLError(.badURL)))),
            annotations: .empty()
        )

        await viewModel.load()

        guard case .loaded(let first, activity: .none) = viewModel.state else {
            return XCTFail("Expected the first page, got \(viewModel.state)")
        }
        XCTAssertEqual(first.count, 20)
        XCTAssertEqual(first.first?.title, "Film 2020")
        XCTAssertEqual(first.first?.awardYear, "2020")
        XCTAssertEqual(first.first?.genreLine, "")
        XCTAssertEqual(first.last?.title, "Film 2001")
        XCTAssertTrue(viewModel.hasMore)
        XCTAssertFalse(first.contains { $0.title == "Nominee" })

        await viewModel.loadMore()

        guard case .loaded(let second, activity: .none) = viewModel.state else {
            return XCTFail("Expected the second page, got \(viewModel.state)")
        }
        XCTAssertEqual(second.map(\.title), (2000...2020).reversed().map { "Film \($0)" })
        XCTAssertFalse(viewModel.hasMore)
    }

    func test_load_usesHydratedTitleWhenDetailSucceeds() async throws {
        let payload = Data(
            #"{"id":872585,"title":"From TMDB","vote_average":8.0,"poster_path":"/from.jpg"}"#.utf8
        )
        let awards = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: [
                AwardCredit(
                    key: "one",
                    family: .academy,
                    category: "Best Picture",
                    categoryID: "Q102427",
                    won: true,
                    year: 2024,
                    title: "Catalog Title",
                    imdbID: nil,
                    wikidataID: nil,
                    work: AwardWork(kind: .movie, movieID: 872585)
                ),
            ]
        ))
        let viewModel = AwardTitlesViewModel(
            request: AwardTitleRequest(family: .academy, category: "Best Picture"),
            awards: awards,
            movies: MovieRepository.test(client: FakeHTTPClient(stub: .success(payload))),
            shows: TVRepository.test(client: FakeHTTPClient(result: .failure(URLError(.badURL)))),
            annotations: .empty()
        )

        await viewModel.load()

        guard case .loaded(let rows, _) = viewModel.state else {
            return XCTFail("Expected a hydrated row, got \(viewModel.state)")
        }
        XCTAssertEqual(rows.first?.title, "From TMDB")
        XCTAssertEqual(rows.first?.awardYear, "2024")
        XCTAssertEqual(rows.first?.imagePath, "/from.jpg")
        XCTAssertEqual(rows.first?.route, .movieDetail(id: 872585))
    }

    private static let pagedCatalog: AwardsCatalog = {
        var credits: [AwardCredit] = (2000...2020).map { year in
            AwardCredit(
                key: "win-\(year)",
                family: .academy,
                category: "Best Picture",
                categoryID: "Q102427",
                won: true,
                year: year,
                title: "Film \(year)",
                imdbID: nil,
                wikidataID: nil,
                work: AwardWork(kind: .movie, movieID: year)
            )
        }
        credits.append(
            AwardCredit(
                key: "nominee",
                family: .academy,
                category: "Best Picture",
                categoryID: "Q102427",
                won: false,
                year: 2024,
                title: "Nominee",
                imdbID: nil,
                wikidataID: nil,
                work: AwardWork(kind: .movie, movieID: 1)
            )
        )
        return AwardsCatalog(generatedAt: Date(timeIntervalSince1970: 1), credits: credits)
    }()
}

