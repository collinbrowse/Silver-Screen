//
//  ReelLoaderTests.swift
//  SilverScreenTests
//
//  The reel loader starts and lands as the app icon, winds the film along its cylinder
//  without the cylinder changing size, travels straight across once leveled, is fully off the
//  frame when it swaps sides, and never drops a piece of film or artwork along the way.
//

import CoreGraphics
import XCTest
@testable import SilverScreen

final class ReelLoaderTests: XCTestCase {
    private let helix = ReelHelix.icon

    func test_winding_throughTheRest_isTheIcon() {
        XCTAssertNil(ReelLoaderMotion.winding(at: 0))
        XCTAssertNil(ReelLoaderMotion.winding(at: ReelLoaderMotion.restShare * 0.9))
        XCTAssertTrue(ReelLoaderMotion.isAtRest(at: 0))
    }

    func test_winding_leavingAndLanding_isTheIconArtworkInPlace() throws {
        for phase in [ReelLoaderMotion.restShare + 0.0001, 0.99999] {
            let winding = try XCTUnwrap(ReelLoaderMotion.winding(at: phase))
            XCTAssertEqual(winding.turn, 0, accuracy: 0.01, "at \(phase)")
            XCTAssertEqual(winding.level, 0, accuracy: 0.001, "at \(phase)")
            XCTAssertEqual(winding.morph, 0, accuracy: 0.001, "at \(phase)")
        }
    }

    func test_flow_wholeTurn_isTheSameSpiralMovedAlongItsAxis() {
        let shift = helix.axisShift(2 * .pi)
        for angle in stride(from: helix.start, through: helix.end, by: 0.25) {
            let resting = helix.section(at: angle)
            let wound = helix.section(at: angle, flow: 2 * .pi)

            XCTAssertEqual(Double(wound.left.x - shift.x), Double(resting.left.x), accuracy: 1e-6)
            XCTAssertEqual(Double(wound.left.y - shift.y), Double(resting.left.y), accuracy: 1e-6)
            XCTAssertEqual(wound.facing, resting.facing, accuracy: 1e-9)
        }
    }

    func test_flow_keepsTheFilmsWidth() {
        func width(_ section: ReelHelix.Section) -> Double {
            Double(hypot(section.right.x - section.left.x, section.right.y - section.left.y))
        }
        for angle in stride(from: helix.start, through: helix.end, by: 0.5) {
            for turn in stride(from: 0.0, to: 2 * .pi, by: 0.7) {
                // Same angle around the cylinder, so the same view of the film. Perspective
                // alone shifts it up to about 2% as it sits nearer or farther along the axis.
                let resting = width(helix.section(at: angle))
                XCTAssertEqual(width(helix.section(at: angle - turn, flow: turn)), resting, accuracy: resting * 0.03)
            }
        }
    }

    func test_axisTilt_climbsToTheRight_likeTheIcon() {
        let along = helix.axisShift(1)

        XCTAssertLessThan(helix.axisTilt, -0.3)
        XCTAssertEqual(Double(along.y / along.x), tan(helix.axisTilt), accuracy: 1e-9)
    }

    func test_film_isOffTheFrame_whenItSwapsSides() {
        // The frame's edges, in the artwork's pixels.
        let margin = (1 / ReelLayout.artWidth - 1) / 2 * Double(ReelHelix.artworkSize.width)
        for angle in stride(from: helix.start, through: helix.end, by: 0.02) {
            for edge in leveled(helix.section(at: angle, flow: ReelLoaderMotion.exitTurn)) {
                XCTAssertGreaterThan(edge.x, Double(ReelHelix.artworkSize.width) + margin, "still on the right")
            }
            for edge in leveled(helix.section(at: angle, flow: -ReelLoaderMotion.entryTurn)) {
                XCTAssertLessThan(edge.x, -margin, "already on the left")
            }
        }
    }

    func test_winding_swapsSidesOnlyOnce_whileLevel() throws {
        var swaps = 0
        var previous: ReelWinding?
        for phase in stride(from: ReelLoaderMotion.restShare + 0.001, to: 1, by: 0.001) {
            let winding = try XCTUnwrap(ReelLoaderMotion.winding(at: phase))
            if let previous, winding.turn < previous.turn - 1 {
                swaps += 1
                XCTAssertEqual(winding.level, 1, accuracy: 0.001, "swaps before it is level")
            }
            previous = winding
        }
        XCTAssertEqual(swaps, 1)
    }

    func test_morphCuts_runAlongTheSpiralInOrder() {
        let angles = ReelMorph.cuts.map(\.angle)

        XCTAssertEqual(angles.first ?? 0, helix.start, accuracy: 1e-4)
        XCTAssertEqual(angles.last ?? 0, helix.end, accuracy: 1e-4)
        XCTAssertEqual(angles, angles.sorted())
    }

    func test_shading_staysPositive_allTheWayAround() {
        for angle in stride(from: 0.0, to: 2 * .pi, by: 0.1) {
            for facing in [-1.0, 0, 1] {
                for x in [0.0, 410, 820] {
                    let gain = ReelShading.gain(angle: angle, facing: facing, x: x)
                    XCTAssertTrue(gain.allSatisfy { $0 >= 0 }, "angle \(angle) facing \(facing) x \(x)")
                }
            }
        }
    }

    func test_scene_atEveryPhase_keepsEveryPieceOfTheFilm() throws {
        let pieces = ReelMorph.cuts.count - 1
        for phase in stride(from: ReelLoaderMotion.restShare + 0.001, to: 1, by: 0.002) {
            let winding = try XCTUnwrap(ReelLoaderMotion.winding(at: phase))
            let scene = ReelScene(winding: winding, visible: -1e9...1e9)

            XCTAssertEqual(Set(scene.slices.map(\.piece)).count, pieces, "drops a piece at \(phase)")
        }
    }

    func test_triangles_crossedQuad_splitsAtTheCrossing() {
        let source = square(side: 1)
        let crossed = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)]

        let triangles = ReelQuad.triangles(from: source, to: crossed)

        XCTAssertEqual(triangles.count, 2)
        XCTAssertEqual(triangles.map { area($0.target) }.reduce(0, +), 50, accuracy: 1e-9)
        for triangle in triangles {
            XCTAssertTrue(triangle.target.contains(CGPoint(x: 5, y: 5)))
        }
    }

    func test_triangles_dentedQuad_splitsAlongTheDiagonalInsideIt() {
        let dented = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 2), CGPoint(x: 10, y: 0), CGPoint(x: 4, y: 10)]

        let triangles = ReelQuad.triangles(from: square(side: 1), to: dented)

        // The quad's own area; the outside diagonal would cover 60.
        XCTAssertEqual(triangles.map { area($0.target) }.reduce(0, +), 40, accuracy: 1e-9)
    }

    func test_triangles_squareQuad_keepsBothHalves() {
        let triangles = ReelQuad.triangles(from: square(side: 1), to: square(side: 8))

        XCTAssertEqual(triangles.map { area($0.target) }.reduce(0, +), 64, accuracy: 1e-9)
    }

    func test_phase_afterElapsedTime_staysWithinOneLoop() {
        let period = ReelLoaderMotion.period

        XCTAssertEqual(ReelLoaderMotion.phase(after: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ReelLoaderMotion.phase(after: period * 1000.25), 0.25, accuracy: 1e-6)
        XCTAssertEqual(ReelLoaderMotion.phase(after: -period * 0.25), 0.75, accuracy: 1e-6)
    }

    private func square(side: CGFloat) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: side), CGPoint(x: 0, y: side)]
    }

    private func area(_ triangle: [CGPoint]) -> Double {
        abs(Double(ReelQuad.turn(triangle[0], triangle[1], triangle[2]))) / 2
    }

    /// The section's edges with the scene tipped fully level, as the loader draws it mid-loop.
    private func leveled(_ section: ReelHelix.Section) -> [CGPoint] {
        let tip = -helix.axisTilt
        let pivot = CGPoint(x: ReelHelix.artworkSize.width / 2, y: ReelHelix.artworkSize.height / 2)
        return [section.left, section.right].map { point in
            let dx = Double(point.x - pivot.x)
            let dy = Double(point.y - pivot.y)
            return CGPoint(
                x: Double(pivot.x) + dx * cos(tip) - dy * sin(tip),
                y: Double(pivot.y) + dx * sin(tip) + dy * cos(tip)
            )
        }
    }
}
