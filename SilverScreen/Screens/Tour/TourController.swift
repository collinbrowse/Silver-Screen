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

    /// What each view carrying an anchor last reported, by the view's source id. Kept
    /// even when the tour is off, because a view reports only when its frame changes,
    /// not when a stop starts. A hidden tab keeps its old frame.
    ///
    /// More than one view can carry an anchor at once: when a fold, unfold, or resize
    /// regroups a grid, the new view appears before the old one is gone, and the old
    /// one can still report a frame from the layout it is leaving.
    @ObservationIgnored private var sightings: [TourAnchor: [UUID: Sighting]] = [:]
    /// Counts appearances so the newest view of an anchor wins.
    @ObservationIgnored private var appearances = 0

    /// Source id for callers that have only one view per anchor, such as tests.
    nonisolated static let soleSource = UUID()
    /// Invisible sightings kept per anchor before the oldest is dropped.
    private static let keptSightings = 4

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
        return String(localized: "\(index + 1) of \(stops.count)")
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
    /// `source` tells apart views that carry the same anchor. A nil `isVisible` (a
    /// frame change) leaves visibility alone, so a view on its way out cannot win
    /// back the highlight by reporting one last frame.
    func report(
        _ anchor: TourAnchor,
        source: UUID = TourController.soleSource,
        frame: CGRect?,
        isVisible: Bool?
    ) {
        var sighting = sightings[anchor]?[source] ?? Sighting()
        if let frame {
            sighting.frame = frame
        }
        if let isVisible {
            if isVisible, !sighting.isVisible {
                appearances += 1
                sighting.order = appearances
            }
            sighting.isVisible = isVisible
        }
        sightings[anchor, default: [:]][source] = sighting
        if isVisible == false {
            prune(anchor)
        }
        if current?.anchors.contains(anchor) == true {
            updateHighlight()
        }
    }

    /// Moves a view's sighting to a new anchor when the view stays on screen but its
    /// anchor changes. No `onAppear` fires for the new anchor and the frame may not
    /// change, so without this the new anchor would never count as visible.
    func reassign(_ old: TourAnchor, to new: TourAnchor, source: UUID) {
        let frame = sightings[old]?[source]?.frame
        report(old, source: source, frame: nil, isVisible: false)
        report(new, source: source, frame: frame, isVisible: true)
    }

    /// Whether the given anchor is laid out on screen right now.
    func isShowing(_ anchor: TourAnchor) -> Bool {
        frame(of: anchor) != nil
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
        let shown = current.anchors.compactMap(frame(of:))
        highlight = shown.dropFirst().reduce(shown.first) { union, frame in union?.union(frame) }
    }

    /// The frame of the newest visible view carrying the anchor that has been placed.
    /// An older view that has not disappeared yet loses to a newer one, because its
    /// frame belongs to the layout it is leaving.
    private func frame(of anchor: TourAnchor) -> CGRect? {
        sightings[anchor]?.values
            .filter { $0.isVisible && $0.frame.map(Self.isPlaced) == true }
            .max { $0.order < $1.order }?
            .frame
    }

    /// Whether a reported frame is a real position on screen. Toolbar items are hosted
    /// in several bridged copies, and each copy first reports a frame centered on the
    /// origin before it is placed. On Mac the newest copy can stay there, which drew
    /// the step 2 ring as a dot in the window's corner. Empty frames are never placed.
    static func isPlaced(_ frame: CGRect) -> Bool {
        guard !frame.isNull, !frame.isInfinite, frame.width >= 1, frame.height >= 1 else { return false }
        return abs(frame.midX) >= 1 || abs(frame.midY) >= 1
    }

    /// Drops the oldest hidden views of an anchor so grid rows that come and go
    /// do not pile up.
    private func prune(_ anchor: TourAnchor) {
        guard let all = sightings[anchor] else { return }
        let hidden = all.filter { !$0.value.isVisible }
        guard hidden.count > Self.keptSightings else { return }
        let dropped = hidden.sorted { $0.value.order < $1.value.order }
            .prefix(hidden.count - Self.keptSightings)
        for (source, _) in dropped {
            sightings[anchor]?[source] = nil
        }
    }
}

/// One view's last report for a tour anchor.
private struct Sighting {
    var frame: CGRect?
    var isVisible = false
    /// When the view last appeared; higher is newer.
    var order = 0
}
