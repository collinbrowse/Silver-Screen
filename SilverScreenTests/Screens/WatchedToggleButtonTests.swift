//
//  WatchedToggleButtonTests.swift
//  SilverScreenTests
//
//  Call sites pass the failure handler as a trailing closure. These pin which
//  callback that closure lands on, so a successful toggle never shows Couldn't Save.
//

import XCTest
@testable import SilverScreen

@MainActor
final class WatchedToggleButtonTests: XCTestCase {
    func test_trailingClosure_bindsToOnFailure() {
        var failures = 0
        let button = WatchedToggleButton(
            draft: movieDraft(),
            lists: .empty(),
            index: ListsIndex()
        ) {
            failures += 1
        }

        button.onFailure()

        XCTAssertEqual(failures, 1)
    }

    func test_trailingClosure_doesNotRunOnToggleComplete() {
        var failures = 0
        let button = WatchedToggleButton(
            draft: movieDraft(),
            lists: .empty(),
            index: ListsIndex()
        ) {
            failures += 1
        }

        button.onToggleComplete()

        XCTAssertEqual(failures, 0)
    }

    private func movieDraft() -> ListItemDraft {
        ListItemDraft(
            id: 1,
            kind: .movie,
            title: "Resident Evil",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 7,
            popularity: 1
        )
    }
}
