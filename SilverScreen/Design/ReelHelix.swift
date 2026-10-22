//
//  ReelHelix.swift
//  SilverScreen
//
//  The app icon's film strip as a spiral wound on a cylinder, and the camera that sees it,
//  fitted to IconReel.png: drawn at rest, the spiral lands on the icon's S. Flowing the film
//  along the spiral screws it along the cylinder, as a real strip would wind.
//

import CoreGraphics
import Foundation

/// A film strip wound in a spiral around a cylinder, and the camera that sees it. Lengths
/// are in the icon artwork's pixels (820 across); angles are radians around the axis.
struct ReelHelix: Sendable {
    var radius: Double
    /// Distance along the axis per radian of turn.
    var advance: Double
    /// Where the icon's film starts and ends, as angles around the axis.
    var start: Double
    var end: Double
    var width: Double
    /// Camera turns applied in order: about the vertical, then the horizontal, then the view axis.
    var yaw: Double
    var pitch: Double
    var roll: Double
    var eyeDistance: Double
    /// Where the axis's zero point lands in the artwork.
    var origin: CGPoint

    /// The size of IconReel.png, the space the spiral was fitted in.
    static let artworkSize = CGSize(width: 820, height: 498)

    /// The spiral fitted to the app icon.
    static let icon = ReelHelix(
        radius: 306.5333,
        advance: 103.4943,
        start: -1.7165,
        end: 4.7483,
        width: 198.9465,
        yaw: 0.5128,
        pitch: 1.6203,
        roll: 0.1353,
        eyeDistance: 7232.2587,
        origin: CGPoint(x: 280.0251, y: 340.2244)
    )

    /// Film length per radian of turn.
    var arcLengthPerRadian: Double { hypot(advance, radius) }

    /// The axis's direction on screen, in radians with y pointing down: negative as it climbs
    /// to the right, as it does in the icon.
    var axisTilt: Double {
        let from = axisShift(0)
        let to = axisShift(1)
        return atan2(to.y - from.y, to.x - from.x)
    }

    /// A cut across the film, as the camera sees it.
    struct Section: Sendable {
        /// The film's two edges and its middle, in the artwork's pixels.
        var left: CGPoint
        var right: CGPoint
        var center: CGPoint
        /// Distance toward the eye; larger is nearer.
        var depth: Double
        /// How squarely the outside faces the viewer: 1 facing, 0 edge-on, -1 showing the inside.
        var facing: Double
    }

    /// The cut across the film at `angle` after the film has flowed `turn` radians along its
    /// spiral. Flowing screws the film along the cylinder; the camera keeps the film the same
    /// size wherever it travels, so the cylinder never seems to grow or shrink.
    func section(at angle: Double, flow turn: Double = 0) -> Section {
        let wound = angle + turn
        let center = ReelVector(x: advance * wound, y: radius * sin(wound), z: -radius * cos(wound))
        let tangent = ReelVector(x: advance, y: radius * cos(wound), z: radius * sin(wound))
        let outward = ReelVector(x: 0, y: sin(wound), z: -cos(wound))
        let across = outward.cross(tangent).normalized.scaled(width / 2)
        let shift = toCamera(ReelVector(x: advance * turn, y: 0, z: 0))
        let place = { (point: ReelVector) -> CGPoint in
            let camera = toCamera(point).minus(shift)
            let perspective = eyeDistance / max(eyeDistance - camera.z, 1)
            return CGPoint(
                x: origin.x + camera.x * perspective + shift.x,
                y: origin.y - camera.y * perspective - shift.y
            )
        }
        let viewCenter = toCamera(center).minus(shift)
        let toEye = ReelVector(x: -viewCenter.x, y: -viewCenter.y, z: eyeDistance - viewCenter.z).normalized
        return Section(
            left: place(center.minus(across)),
            right: place(center.plus(across)),
            center: place(center),
            depth: viewCenter.z,
            facing: toCamera(outward).dot(toEye)
        )
    }

    /// How far the film has moved on screen, in the artwork's pixels, after flowing `turn`.
    func axisShift(_ turn: Double) -> CGPoint {
        let shift = toCamera(ReelVector(x: advance * turn, y: 0, z: 0))
        return CGPoint(x: shift.x, y: -shift.y)
    }

    private func toCamera(_ point: ReelVector) -> ReelVector {
        var (x, y, z) = (point.x, point.y, point.z)
        (x, z) = (x * cos(yaw) + z * sin(yaw), -x * sin(yaw) + z * cos(yaw))
        (y, z) = (y * cos(pitch) - z * sin(pitch), y * sin(pitch) + z * cos(pitch))
        (x, y) = (x * cos(roll) - y * sin(roll), x * sin(roll) + y * cos(roll))
        return ReelVector(x: x, y: y, z: z)
    }
}

/// A small 3D vector for the spiral's math.
struct ReelVector: Sendable {
    var x: Double
    var y: Double
    var z: Double

    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var normalized: ReelVector { scaled(1 / max(length, 1e-12)) }

    func scaled(_ factor: Double) -> ReelVector { ReelVector(x: x * factor, y: y * factor, z: z * factor) }
    func plus(_ other: ReelVector) -> ReelVector { ReelVector(x: x + other.x, y: y + other.y, z: z + other.z) }
    func minus(_ other: ReelVector) -> ReelVector { ReelVector(x: x - other.x, y: y - other.y, z: z - other.z) }
    func dot(_ other: ReelVector) -> Double { x * other.x + y * other.y + z * other.z }

    func cross(_ other: ReelVector) -> ReelVector {
        ReelVector(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
    }
}
