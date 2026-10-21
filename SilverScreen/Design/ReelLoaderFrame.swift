//
//  ReelLoaderFrame.swift
//  SilverScreen
//
//  Draws the app icon's film strip, and its shadow on the floor, at one moment of a
//  `ReelLoaderMotion`. At rest it is the icon artwork itself. As a loop starts, the whole
//  scene tips the cylinder level while each traced piece of the artwork moves onto the
//  flowing spiral and its pixels blend into the 3D film, made from the icon's own weave and
//  teal and lit around the cylinder; landing runs the same in reverse. Pieces are drawn far
//  first so the back of the cylinder passes behind the front.
//

import SwiftUI

/// Layout of the strip inside a square loader frame, in fractions of the frame's width.
enum ReelLayout {
    /// The strip's width when it rests in the icon pose. The cylinder it winds around is about
    /// a quarter taller than the icon, and the frame leaves room for all of it.
    static let artWidth = 0.7
    /// The strip's resting center, a touch above the frame's center to leave room for the shadow.
    static let restY = -0.03
    /// Center of the shadow on the floor, below the cylinder's lowest reach.
    static let floorY = 0.33
    /// How flat the shadow is next to the strip's own height.
    static let shadowSquash = 0.16
    static let shadowOpacity = 0.3
    /// Shadow blur as a fraction of the strip's width.
    static let shadowBlur = 0.035
    /// How much faster the film under the artwork turns solid than the shape morphs.
    static let filmFadeIn = 6.0
    /// How far into the morph the icon artwork has faded out. Finishing early keeps the icon's
    /// perforations from ghosting through the 3D film's, which sit in different places.
    static let artFadeOut = 0.5
}

/// The film texture in IconReelFilm.png: two copies of a two-frame tile side by side, so any
/// short run of film can be read without wrapping.
enum ReelFilmTile {
    /// One tile's length along the film, in the image's pixels: two frames.
    static let period = 402.0
    /// One frame's length.
    static let frame = 201.0
    /// The film's width across the image.
    static let across = 240.0
    /// Offset along the tile that lines its frame gaps up with the icon's.
    static let phase = 63.84
}

/// How the film is lit, measured from the icon: the icon's color over the film texture's,
/// per channel, fitted against the film's angle around the cylinder. The inside of the film,
/// seen around the back, also shades across the film's width of the screen, as the icon
/// shades the insides of its two side runs differently.
enum ReelShading {
    /// Per channel: a constant, then cos and sin of one, two and three times the angle, then
    /// the back face's sideways term.
    static let gains: [[Double]] = [
        [1.1540, 0.3561, 0.2402, 0.1859, 0.8234, 0.2693, 0.1056, -0.5914],
        [1.0008, 0.1946, 0.1485, 0.0534, 0.5572, 0.2173, 0.0400, -0.4023],
        [0.9802, 0.1603, 0.1277, 0.0321, 0.4817, 0.1938, 0.0279, -0.3439],
    ]

    /// Red, green and blue gains for film at `angle` around the cylinder, facing the viewer
    /// by `facing` (`ReelHelix.Section.facing`), whose middle sits `x` pixels across the film's
    /// resting place.
    static func gain(angle: Double, facing: Double, x: Double) -> [Double] {
        let sideways = min(max((x - 410) / 410, -1), 1)
        let terms = [
            1, cos(angle), sin(angle), cos(2 * angle), sin(2 * angle), cos(3 * angle), sin(3 * angle),
            max(0, -facing) * sideways,
        ]
        return gains.map { row in max(0, zip(row, terms).reduce(0) { $0 + $1.0 * $1.1 }) }
    }
}

/// One still of a reel loader at `phase`, over its floor shadow.
struct ReelLoaderFrame: View {
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let reel = context.resolve(Image("IconReel"))
            let film = context.resolve(Image("IconReelFilm"))
            let side = size.width
            let artWidth: CGFloat = side * ReelLayout.artWidth
            let pixel: CGFloat = artWidth / ReelHelix.artworkSize.width
            let art = CGRect(
                x: (side - artWidth) / 2,
                y: size.height / 2 + ReelLayout.restY * side - ReelHelix.artworkSize.height * pixel / 2,
                width: artWidth,
                height: ReelHelix.artworkSize.height * pixel
            )
            let place = { (point: CGPoint) in CGPoint(x: art.minX + point.x * pixel, y: art.minY + point.y * pixel) }
            let winding = ReelLoaderMotion.winding(at: phase)
            // The frame's edges, in the artwork's pixels.
            let scene = ReelScene(
                winding: winding,
                visible: (-art.minX / pixel)...((side - art.minX) / pixel)
            ).placed(by: place)

            var shadows = context
            shadows.opacity = ReelLayout.shadowOpacity
            shadows.drawLayer { layer in
                layer.addFilter(.blur(radius: artWidth * ReelLayout.shadowBlur))
                let floor = size.height / 2 + ReelLayout.floorY * side
                for slice in scene.slices {
                    var outline = Path()
                    outline.addLines(slice.film.map {
                        CGPoint(x: $0.x, y: floor + ReelLayout.shadowSquash * ($0.y - art.midY))
                    })
                    outline.closeSubpath()
                    layer.fill(outline, with: .color(.black))
                }
            }

            guard let winding else {
                context.draw(reel, in: art)
                return
            }
            if winding.morph >= ReelLayout.artFadeOut {
                for slice in scene.slices {
                    slice.draw(film, context: context)
                }
                return
            }
            // The film lies underneath, solid within moments of leaving the icon, and the
            // artwork's pieces fade out on top of it, both on the same moving shape. Wherever the
            // film reaches past the artwork's own pixels it is already solid, so no part of the
            // strip shows through.
            var strip = context
            strip.opacity = min(1, winding.morph * ReelLayout.filmFadeIn)
            strip.drawLayer { layer in
                for slice in scene.slices {
                    slice.draw(film, context: layer)
                }
            }
            var icon = context
            icon.opacity = 1 - ReelEase.smooth(winding.morph / ReelLayout.artFadeOut)
            icon.drawLayer { layer in
                for slice in scene.slices {
                    slice.drawArtwork(reel, in: art, film: film, context: layer)
                }
            }
        }
        // The film leaves and comes back through the sides, so they fade instead of cutting it off.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.1),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

/// Everything a loader draws at one moment: slices of the film, each carrying both the 3D
/// film's texture and the icon artwork's own piece, so the two always share one shape.
/// Positions are in the artwork's pixels until `placed(by:)`.
struct ReelScene {
    var slices: [ReelFilmSlice]

    /// Slices that land at least partly inside `visible`, drawn this many to a piece between
    /// two traced cuts where the film faces the viewer, and more where it turns edge-on over
    /// the top or under the bottom of the cylinder, so each fold there stays tiny.
    static let slicesPerPiece = 1
    static let slicesPerEdgeOnPiece = 3
    /// Where the icon and the 3D film disagree about which edge is which (in the curl and the
    /// fold), a piece turns over as it morphs; many slices let it turn smoothly.
    static let slicesPerTurningPiece = 8

    /// The scene for `winding`, or for the icon pose when it is nil, sorted far to near.
    init(winding: ReelWinding?, visible: ClosedRange<CGFloat>, helix: ReelHelix = .icon) {
        let cuts = ReelMorph.cuts
        let turn = winding?.turn ?? 0
        let morph = winding?.morph ?? 0
        let texturePerRadian = helix.arcLengthPerRadian * ReelFilmTile.across / helix.width
        let travelled = helix.axisShift(turn).x
        // Tip the whole scene about the artwork's middle until the cylinder's axis is level.
        let tip = -helix.axisTilt * (winding?.level ?? 0)
        let pivot = CGPoint(x: ReelHelix.artworkSize.width / 2, y: ReelHelix.artworkSize.height / 2)
        let place = { (traced: CGPoint, film: CGPoint) -> CGPoint in
            let mixed = CGPoint(x: traced.x + (film.x - traced.x) * morph, y: traced.y + (film.y - traced.y) * morph)
            let dx = mixed.x - pivot.x
            let dy = mixed.y - pivot.y
            return CGPoint(
                x: pivot.x + dx * CGFloat(cos(tip)) - dy * CGFloat(sin(tip)),
                y: pivot.y + dx * CGFloat(sin(tip)) + dy * CGFloat(cos(tip))
            )
        }
        // The film `fraction` of the way from cut `index` to the next: the traced icon there and
        // the 3D film there, matched edge to edge, blended by `morph`. The traced points are
        // kept too, as the part of the icon artwork that rides along.
        let sample = { (index: Int, fraction: Double) -> (left: CGPoint, right: CGPoint, tracedLeft: CGPoint, tracedRight: CGPoint, angle: Double, section: ReelHelix.Section) in
            let near = cuts[index]
            let far = cuts[min(index + 1, cuts.count - 1)]
            let nearEdges = near.swapped ? (near.right, near.left) : (near.left, near.right)
            let farEdges = far.swapped ? (far.right, far.left) : (far.left, far.right)
            let blend = { (a: CGPoint, b: CGPoint, t: Double) in
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            let angle = near.angle + (far.angle - near.angle) * fraction
            let section = helix.section(at: angle, flow: turn)
            let tracedLeft: CGPoint
            let tracedRight: CGPoint
            if near.swapped == far.swapped {
                tracedLeft = blend(nearEdges.0, farEdges.0, fraction)
                tracedRight = blend(nearEdges.1, farEdges.1, fraction)
            } else {
                // The icon and the 3D film disagree about which edge is which past this piece.
                // Its ends run along the icon's own edges to the far cut, sweeping the whole
                // piece; the band that trades them over is added after.
                tracedLeft = blend(nearEdges.0, farEdges.1, fraction)
                tracedRight = blend(nearEdges.1, farEdges.0, fraction)
            }
            return (
                place(tracedLeft, section.left),
                place(tracedRight, section.right),
                tracedLeft,
                tracedRight,
                angle,
                section
            )
        }
        let onScreen = { (quad: [CGPoint]) -> Bool in
            let xs = quad.map(\.x)
            guard let low = xs.min(), let high = xs.max() else { return false }
            return high > visible.lowerBound && low < visible.upperBound
        }
        let atCuts = cuts.indices.map { sample($0, 0) }

        var slices: [ReelFilmSlice] = []
        for index in 0..<(cuts.count - 1) {
            let near = atCuts[index]
            let far = sample(index, 1)
            let edgeOn = min(abs(near.section.facing), abs(far.section.facing)) < 0.35
                || near.section.facing * far.section.facing < 0
            let count = cuts[index].swapped != cuts[index + 1].swapped
                ? Self.slicesPerTurningPiece
                : (edgeOn ? Self.slicesPerEdgeOnPiece : Self.slicesPerPiece)
            let points = [near] + (1..<count).map { sample(index, Double($0) / Double(count)) } + [far]
            for step in 0..<count {
                let a = points[step]
                let b = points[step + 1]
                let film = [a.left, b.left, b.right, a.right]
                guard onScreen(film) else { continue }
                let start = ((a.angle - helix.start) * texturePerRadian + ReelFilmTile.phase)
                    .truncatingRemainder(dividingBy: ReelFilmTile.period)
                slices.append(ReelFilmSlice(
                    piece: index,
                    film: film,
                    artSource: [a.tracedLeft, b.tracedLeft, b.tracedRight, a.tracedRight],
                    textureStart: start,
                    textureLength: (b.angle - a.angle) * texturePerRadian,
                    depth: (a.section.depth + b.section.depth) / 2,
                    gain: ReelShading.gain(
                        angle: (a.angle + b.angle) / 2 + turn,
                        facing: (a.section.facing + b.section.facing) / 2,
                        x: Double((a.section.center.x + b.section.center.x) / 2 - travelled)
                    )
                ))
            }

            // Where a piece turns over, it ends with its edges crossed over the next piece's start.
            // The band between the two (the next cut, once each way round) fills the gap; it
            // shrinks to nothing as the loop leaves the icon and again once the film is fully 3D.
            if cuts[index].swapped != cuts[index + 1].swapped {
                let next = atCuts[index + 1]
                let band = [far.left, next.left, far.right, next.right]
                if onScreen(band) {
                    // The band runs along the cut, so it shows a picture of the film texture
                    // rather than the bare film between pictures.
                    let along = ((next.angle - helix.start) * texturePerRadian + ReelFilmTile.phase)
                        .truncatingRemainder(dividingBy: ReelFilmTile.period)
                    let frameStart = (along / ReelFilmTile.frame).rounded(.down) * ReelFilmTile.frame
                    slices.append(ReelFilmSlice(
                        piece: index,
                        film: band,
                        artSource: [far.tracedLeft, next.tracedLeft, far.tracedRight, next.tracedRight],
                        textureStart: frameStart + ReelFilmTile.frame * 0.2,
                        textureLength: ReelFilmTile.frame * 0.6,
                        depth: next.section.depth,
                        gain: ReelShading.gain(
                            angle: next.angle + turn,
                            facing: next.section.facing,
                            x: Double(next.section.center.x - travelled)
                        )
                    ))
                }
            }
        }
        self.slices = slices.sorted { $0.depth < $1.depth }
    }

    func placed(by place: (CGPoint) -> CGPoint) -> ReelScene {
        var placed = self
        placed.slices = slices.map { slice in
            var moved = slice
            moved.film = slice.film.map(place)
            moved.artSource = slice.artSource.map(place)
            return moved
        }
        return placed
    }
}

/// A slice of the film: where it lands, the stretch of film texture that covers it, and the
/// part of the icon artwork it carries. Corners run along the film's left edge, then back
/// along its right.
struct ReelFilmSlice {
    /// The piece between two traced cuts this slice belongs to.
    var piece: Int
    var film: [CGPoint]
    /// The slice's part of the icon artwork, corner for corner with `film`.
    var artSource: [CGPoint]
    /// Where the slice starts along the film texture, and how much of it the slice covers.
    var textureStart: Double
    var textureLength: Double
    /// Distance toward the viewer, for drawing far slices first.
    var depth: Double
    /// Red, green and blue gains for the light on the visible face.
    var gain: [Double]

    /// Lays this stretch of the film texture onto the slice, lit for where it faces.
    func draw(_ image: GraphicsContext.ResolvedImage, context: GraphicsContext) {
        let start = CGFloat(textureStart)
        let end = CGFloat(textureStart + textureLength)
        let across = CGFloat(ReelFilmTile.across)
        let source = [CGPoint(x: start, y: 0), CGPoint(x: end, y: 0), CGPoint(x: end, y: across), CGPoint(x: start, y: across)]
        let texture = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        var matrix = ColorMatrix()
        matrix.r1 = Float(gain[0])
        matrix.g2 = Float(gain[1])
        matrix.b3 = Float(gain[2])
        var lit = context
        lit.addFilter(.colorMatrix(matrix))
        ReelQuad.draw(image, in: texture, from: source, to: film, context: lit)
    }

    /// Lays the slice's part of the icon artwork onto where it now lands. Around the curl and
    /// the fold the icon draws the film as wedges, so part of a slice there has no artwork to
    /// stretch once it opens up; the 3D film fills that part instead.
    func drawArtwork(
        _ image: GraphicsContext.ResolvedImage,
        in artwork: CGRect,
        film filmImage: GraphicsContext.ResolvedImage,
        context: GraphicsContext
    ) {
        ReelQuad.draw(image, in: artwork, from: artSource, to: film, context: context) { filler in
            draw(filmImage, context: filler)
        }
    }
}

/// Maps a four-cornered piece of an image onto a four-cornered piece of the canvas.
enum ReelQuad {
    /// A triangle of the image and where it lands.
    struct Triangle {
        var source: [CGPoint]
        var target: [CGPoint]
    }

    /// Triangles that together cover `target`, each with the matching part of `source`. A
    /// convex or dented quad splits along a diagonal that lies inside it. Where the film turns
    /// edge-on the quad folds over and crosses itself; it then splits at the crossing into the
    /// two triangles it covers, so no part of the film is dropped.
    static func triangles(from source: [CGPoint], to target: [CGPoint]) -> [Triangle] {
        let pick = { (corners: [Int]) in Triangle(source: corners.map { source[$0] }, target: corners.map { target[$0] }) }
        if turn(target[0], target[1], target[2]) * turn(target[0], target[2], target[3]) >= 0 {
            return [pick([0, 2, 1]), pick([0, 2, 3])]
        }
        if turn(target[1], target[2], target[3]) * turn(target[1], target[3], target[0]) >= 0 {
            return [pick([1, 3, 2]), pick([1, 3, 0])]
        }
        for (a, b, c, d) in [(0, 1, 2, 3), (1, 2, 3, 0)] {
            guard let (s, u) = crossing(target[a], target[b], target[c], target[d]) else { continue }
            let point = lerp(target[a], target[b], s)
            return [
                Triangle(source: [source[a], lerp(source[a], source[b], s), source[d]], target: [target[a], point, target[d]]),
                Triangle(source: [lerp(source[c], source[d], u), source[b], source[c]], target: [point, target[b], target[c]]),
            ]
        }
        return [pick([0, 2, 1]), pick([0, 2, 3])]
    }

    /// Draws `image` (laid out in `rect`) so the quad `source` lands on `target`. A triangle
    /// whose part of `source` is too thin to draw is handed to `fill`, if given, with a context
    /// clipped to where that triangle lands.
    static func draw(
        _ image: GraphicsContext.ResolvedImage,
        in rect: CGRect,
        from source: [CGPoint],
        to target: [CGPoint],
        context: GraphicsContext,
        fill: ((GraphicsContext) -> Void)? = nil
    ) {
        let overlap: CGFloat = 0.6
        let quadArea = abs(turn(source[0], source[1], source[2])) + abs(turn(source[0], source[2], source[3]))
        for triangle in triangles(from: source, to: target) {
            let corners = triangle.source
            // Pieces fanned around the icon's curls taper to a point; a sliver half has no area
            // to draw.
            guard abs(turn(corners[0], corners[1], corners[2])) > 0.02 * quadArea else {
                if let fill {
                    var filler = context
                    filler.clip(to: Path { path in
                        path.addLines(grown(triangle.target, by: 0.75))
                        path.closeSubpath()
                    })
                    fill(filler)
                }
                continue
            }
            guard let transform = affine(from: corners, to: triangle.target) else { continue }
            let bounds = corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            var piece = context
            piece.concatenate(transform)
            // Hard-edged clips meet without the faint seams antialiasing leaves; each triangle
            // overhangs its neighbors by a hair.
            piece.clip(to: Path(bounds.insetBy(dx: -2, dy: -2)), style: FillStyle(antialiased: false))
            for (from, to, opposite) in [(0, 1, 2), (1, 2, 0), (2, 0, 1)] {
                let edge = side(
                    of: corners[from],
                    corners[to],
                    toward: corners[opposite],
                    overlap: overlap,
                    reach: bounds.width + bounds.height + 10
                )
                piece.clip(to: edge, style: FillStyle(antialiased: false))
            }
            piece.draw(image, in: rect)
        }
    }

    /// Twice the signed area of the triangle `a`, `b`, `c`: positive one way round, negative
    /// the other.
    static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
    }

    /// The triangle with each corner pushed out from its middle by `distance`.
    private static func grown(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: (points[0].x + points[1].x + points[2].x) / 3, y: (points[0].y + points[1].y + points[2].y) / 3)
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = max(hypot(dx, dy), 0.001)
            return CGPoint(x: point.x + dx / length * distance, y: point.y + dy / length * distance)
        }
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Where segment `a`–`b` crosses segment `c`–`d`, as fractions along each, or nil when
    /// they do not cross.
    private static func crossing(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> (CGFloat, CGFloat)? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let q = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denominator = r.x * q.y - r.y * q.x
        guard abs(denominator) > 1e-9 else { return nil }
        let s = ((c.x - a.x) * q.y - (c.y - a.y) * q.x) / denominator
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
        guard (0...1).contains(s), (0...1).contains(u) else { return nil }
        return (s, u)
    }

    /// Everything on `point`'s side of the line through `start` and `end`, plus `overlap`
    /// past the line.
    private static func side(of start: CGPoint, _ end: CGPoint, toward point: CGPoint, overlap: CGFloat, reach: CGFloat) -> Path {
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001)
        let along = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        var normal = CGPoint(x: -along.y, y: along.x)
        if (point.x - start.x) * normal.x + (point.y - start.y) * normal.y < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let corner = { (a: CGFloat, n: CGFloat) in
            CGPoint(x: start.x + along.x * a + normal.x * n, y: start.y + along.y * a + normal.y * n)
        }
        return Path { path in
            path.addLines([
                corner(-reach, -overlap),
                corner(length + reach, -overlap),
                corner(length + reach, reach),
                corner(-reach, reach),
            ])
            path.closeSubpath()
        }
    }

    /// The map that carries triangle `source` onto `target`, or nil when either is too thin
    /// to draw.
    private static func affine(from source: [CGPoint], to target: [CGPoint]) -> CGAffineTransform? {
        let s1 = CGPoint(x: source[1].x - source[0].x, y: source[1].y - source[0].y)
        let s2 = CGPoint(x: source[2].x - source[0].x, y: source[2].y - source[0].y)
        let t1 = CGPoint(x: target[1].x - target[0].x, y: target[1].y - target[0].y)
        let t2 = CGPoint(x: target[2].x - target[0].x, y: target[2].y - target[0].y)
        let determinant = s1.x * s2.y - s2.x * s1.y
        guard abs(determinant) > 1e-6, abs(t1.x * t2.y - t2.x * t1.y) > 1e-4 else { return nil }
        // Solve M * [s1 s2] = [t1 t2].
        let a = (t1.x * s2.y - t2.x * s1.y) / determinant
        let c = (t2.x * s1.x - t1.x * s2.x) / determinant
        let b = (t1.y * s2.y - t2.y * s1.y) / determinant
        let d = (t2.y * s1.x - t1.y * s2.x) / determinant
        return CGAffineTransform(
            a: a,
            b: b,
            c: c,
            d: d,
            tx: target[0].x - (a * source[0].x + c * source[0].y),
            ty: target[0].y - (b * source[0].x + d * source[0].y)
        )
    }
}

#Preview("Resting") {
    ReelLoaderFrame(phase: 0)
        .frame(width: 240, height: 240)
}

#Preview("Winding") {
    ReelLoaderFrame(phase: 0.4)
        .frame(width: 240, height: 240)
}
