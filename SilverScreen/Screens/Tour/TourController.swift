//
//  TourController.swift
//  SilverScreen
//
//  Runs the feature tour: moves through the stops, takes the app to each one
//  through `AppRouter`, and tracks where the highlighted views are on screen.
//

import CoreGraphics
import Foundation

/// The tour's state. Built once in `SceneDelegate`; onboarding's finish starts it.
@Observable
@MainActor
final class TourController {
    private(set) var stops: [TourStop] = []
    /// Index into `stops` while the tour is showing; nil when it is not running.
    private(set) var index: Int?
    /// Window-space union of the current stop's visible anchors. Nil until one reports.
    private(set) var highlight: CGRect?

    /// Last reported window frame per anchor. Kept even when the tour is off, because
    /// a view reports only when its frame changes, not when a stop starts.
    @ObservationIgnored private var frames: [TourAnchor: CGRect] = [:]
    /// Anchors whose view is on screen. A hidden tab keeps its old frame.
    @ObservationIgnored private var visible: Set<TourAnchor> = []

    private let router: AppRouter
    private let lists: ListsRepository

    init(router: AppRouter, lists: ListsRepository) {
        self.router = router
        self.lists = lists
    }

    var current: TourStop? {
        guard let index, stops.indices.contains(index) else { return nil }
        return stops[index]
    }

    var isActive: Bool { current != nil }
    var isLastStop: Bool { index == stops.count - 1 }

    /// "2 of 6".
    var progressText: String {
        guard let index else { return "" }
        return "\(index + 1) of \(stops.count)"
    }

    /// Plans the stops from the library and opens the first one.
    func start() async {
        let snapshot = (try? await lists.snapshot()) ?? LibrarySnapshot(lists: [], entries: [])
        stops = TourStop.plan(for: snapshot)
        show(0)
    }

    func next() {
        guard let index else { return }
        if index + 1 < stops.count {
            show(index + 1)
        } else {
            finish()
        }
    }

    /// Ends the tour early. Same landing as the last stop.
    func skip() {
        finish()
    }

    /// Called by `.tourAnchor` when a marked view moves, appears, or disappears.
    func report(_ anchor: TourAnchor, frame: CGRect?, isVisible: Bool) {
        if let frame {
            frames[anchor] = frame
        }
        if isVisible {
            visible.insert(anchor)
        } else {
            visible.remove(anchor)
        }
        if current?.anchors.contains(anchor) == true {
            updateHighlight()
        }
    }

    /// Whether the given anchor is laid out on screen right now.
    func isShowing(_ anchor: TourAnchor) -> Bool {
        visible.contains(anchor) && frames[anchor] != nil
    }

    private func show(_ newIndex: Int) {
        guard stops.indices.contains(newIndex) else { return finish() }
        index = newIndex
        navigate(to: stops[newIndex])
        updateHighlight()
    }

    /// Back on the Library root, where onboarding left off.
    private func finish() {
        index = nil
        highlight = nil
        router.favorites.popToRoot()
        router.openLibrary()
    }

    private func navigate(to stop: TourStop) {
        switch stop {
            case .libraryLists, .newList:
                router.favorites.popToRoot()
                router.selectedTab = .library
            case .eyeButton:
                router.browse.popToRoot()
                router.selectedTab = .browse
            case .awards:
                router.search.popToRoot()
                router.selectedTab = .search
            case .rateMovie(let id, _):
                router.favorites.path = [.movieDetail(id: id)]
                router.selectedTab = .library
            case .trackSeries(let id, _):
                router.favorites.path = [.tvSeries(id: id)]
                router.selectedTab = .library
        }
    }

    private func updateHighlight() {
        guard let current else {
            highlight = nil
            return
        }
        let shown = current.anchors.compactMap { visible.contains($0) ? frames[$0] : nil }
        highlight = shown.dropFirst().reduce(shown.first) { union, frame in union?.union(frame) }
    }
}
