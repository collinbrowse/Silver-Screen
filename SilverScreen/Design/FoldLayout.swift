//
//  FoldLayout.swift
//  SilverScreen
//
//  Where a fold (the iPhone Duo's crease) crosses a view, as two panes and the
//  gutter between them. Pure geometry: `FoldPanes.swift` reads the crease from the
//  system and these types decide the layout, so the rules are unit tested.
//

import CoreGraphics

/// A crease the system reports, in the reading view's own coordinates.
struct FoldDivision: Equatable, Sendable {
    let frame: CGRect
    /// Space the system asks content to keep on each side of the crease.
    var leadingMargin: CGFloat = 0
    var trailingMargin: CGFloat = 0
}

/// A view split by a vertical crease into a leading and a trailing pane. Content
/// goes in the panes; nothing goes in the gutter (the crease plus its margins).
/// All rects are in the view's own coordinates and span its full height.
struct FoldSplit: Equatable, Sendable {
    let leading: CGRect
    let gutter: CGRect
    let trailing: CGRect
}

enum FoldLayout {
    /// Narrowest pane worth laying content into. A crease nearer the view's edge
    /// than this is left alone and the view keeps its one-piece layout.
    static let minimumPaneWidth: CGFloat = 120

    /// Splits `bounds` at the first vertical division that crosses it, or returns nil
    /// when none does (every iPhone and iPad, the Duo shut, the Duo upright). The
    /// system can report divisions outside the view, so each is tested against
    /// `bounds`. The gutter is the crease widened by its margins.
    static func split(bounds: CGRect, divisions: [FoldDivision]) -> FoldSplit? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        for division in divisions {
            let crease = division.frame
            // A vertical crease is taller than it is wide and overlaps the view vertically.
            guard crease.height > crease.width,
                  crease.maxY > bounds.minY, crease.minY < bounds.maxY
            else { continue }
            let gutterMinX = max(bounds.minX, crease.minX - division.leadingMargin)
            let gutterMaxX = min(bounds.maxX, crease.maxX + division.trailingMargin)
            let leadingWidth = gutterMinX - bounds.minX
            let trailingWidth = bounds.maxX - gutterMaxX
            guard leadingWidth >= minimumPaneWidth, trailingWidth >= minimumPaneWidth else { continue }
            return FoldSplit(
                leading: CGRect(x: bounds.minX, y: bounds.minY, width: leadingWidth, height: bounds.height),
                gutter: CGRect(x: gutterMinX, y: bounds.minY, width: gutterMaxX - gutterMinX, height: bounds.height),
                trailing: CGRect(x: gutterMaxX, y: bounds.minY, width: trailingWidth, height: bounds.height)
            )
        }
        return nil
    }

    /// Items per pane for a grid of cards at least `minimumCardWidth` wide, the same
    /// in both panes so rows line up across the gutter. `sideInset` is the page margin
    /// each pane keeps at its outer edge. Never below one.
    static func columnsPerPane(
        split: FoldSplit,
        minimumCardWidth: CGFloat,
        spacing: CGFloat,
        sideInset: CGFloat = 0
    ) -> Int {
        let narrowest = min(split.leading.width, split.trailing.width) - sideInset
        let fitting = Int((narrowest + spacing) / (minimumCardWidth + spacing))
        return max(fitting, 1)
    }

    /// Splits `items` row by row across two panes of `perPane` columns each: each
    /// row's first `perPane` items go leading, the rest trailing. Reading order is
    /// kept: left to right, then down.
    static func distribute<Item>(_ items: [Item], perPane: Int) -> (leading: [Item], trailing: [Item]) {
        let size = max(perPane, 1)
        var leading: [Item] = []
        var trailing: [Item] = []
        for (index, item) in items.enumerated() {
            if (index / size).isMultiple(of: 2) {
                leading.append(item)
            } else {
                trailing.append(item)
            }
        }
        return (leading, trailing)
    }
}
