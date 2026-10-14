import Foundation
import Model
import SwiftUI

// The squad pet's accessories (M7, Squad Boost): a scarf, a party hat, a flower crown, glasses, a
// bow and a star clip, drawn on the pet in shapes like everything else here, so they work in the
// widget extension and the Live Activity. None on an egg.
//
// Each one is sized with the stage (`accessoryScale`), a little bigger below `detailFrom` where it
// also drops its small parts (the hat's dots, the crown's petals and leaves, the lenses), and stays
// inside the pet's square. Always-On draws them as outlines. Where they sit on each species' head
// (`PetHead`) was tuned in a Python prototype of this file, mirroring `PetGeometry`, at 18, 64 and
// 120 points in every species and stage.

/// Where things sit on a pet's head, in its body's frame (`PetGeometry.inBody`): (0, 0) is the
/// body's top left and (1, 1) its bottom right. Per species, and per stage where the head's outline
/// changes (the puff's scallops, the ember's tips).
struct PetHead: Sendable {
    /// A point on the body, and how far what sits there leans.
    struct Anchor: Sendable {
        let u: CGFloat
        let v: CGFloat
        /// Degrees; positive leans right.
        let tilt: Double
    }

    /// The middle of the party hat's base.
    let hat: Anchor
    /// The bow's knot, on the head's right shoulder.
    let bow: Anchor
    /// The star clip, on the left.
    let clip: Anchor
    /// The flower crown's five flowers, left to right, just inside the top of the head.
    let crown: [CGPoint]

    static let puffBaby = PetHead(
        hat: Anchor(u: 0.58, v: 0.05, tilt: 12),
        bow: Anchor(u: 0.83, v: 0.20, tilt: 28),
        clip: Anchor(u: 0.20, v: 0.17, tilt: -24),
        crown: [CGPoint(x: 0.16, y: 0.22), CGPoint(x: 0.30, y: 0.10), CGPoint(x: 0.47, y: 0.07), CGPoint(x: 0.64, y: 0.06), CGPoint(x: 0.80, y: 0.16)]
    )

    static let puffTeen = PetHead(
        hat: Anchor(u: 0.47, v: 0.03, tilt: 10),
        bow: Anchor(u: 0.84, v: 0.18, tilt: 28),
        clip: Anchor(u: 0.17, v: 0.27, tilt: -24),
        crown: [CGPoint(x: 0.18, y: 0.26), CGPoint(x: 0.33, y: 0.07), CGPoint(x: 0.49, y: 0.02), CGPoint(x: 0.66, y: 0.09), CGPoint(x: 0.82, y: 0.16)]
    )

    static let puffAdult = PetHead(
        hat: Anchor(u: 0.56, v: 0.00, tilt: 10),
        bow: Anchor(u: 0.85, v: 0.18, tilt: 28),
        clip: Anchor(u: 0.24, v: 0.13, tilt: -24),
        crown: [CGPoint(x: 0.22, y: 0.14), CGPoint(x: 0.36, y: 0.07), CGPoint(x: 0.52, y: 0.02), CGPoint(x: 0.68, y: 0.06), CGPoint(x: 0.83, y: 0.16)]
    )

    /// The hat sits over the stem, so the leaves come out from under it.
    static let sprout = PetHead(
        hat: Anchor(u: 0.50, v: 0.07, tilt: 8),
        bow: Anchor(u: 0.82, v: 0.18, tilt: 30),
        clip: Anchor(u: 0.19, v: 0.18, tilt: -26),
        crown: [CGPoint(x: 0.18, y: 0.20), CGPoint(x: 0.32, y: 0.09), CGPoint(x: 0.50, y: 0.06), CGPoint(x: 0.68, y: 0.09), CGPoint(x: 0.82, y: 0.20)]
    )

    /// The hat covers the flame's tip; the crown rings the flame below its tips.
    static let emberBaby = PetHead(
        hat: Anchor(u: 0.55, v: 0.20, tilt: 8),
        bow: Anchor(u: 0.80, v: 0.42, tilt: 24),
        clip: Anchor(u: 0.22, v: 0.44, tilt: -22),
        crown: [CGPoint(x: 0.16, y: 0.44), CGPoint(x: 0.32, y: 0.36), CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.68, y: 0.34), CGPoint(x: 0.84, y: 0.42)]
    )

    static let emberTeen = PetHead(
        hat: Anchor(u: 0.60, v: 0.19, tilt: 10),
        bow: Anchor(u: 0.84, v: 0.40, tilt: 24),
        clip: Anchor(u: 0.20, v: 0.44, tilt: -22),
        crown: [CGPoint(x: 0.14, y: 0.46), CGPoint(x: 0.30, y: 0.42), CGPoint(x: 0.48, y: 0.38), CGPoint(x: 0.66, y: 0.36), CGPoint(x: 0.84, y: 0.42)]
    )

    static let emberAdult = PetHead(
        hat: Anchor(u: 0.52, v: 0.20, tilt: 4),
        bow: Anchor(u: 0.84, v: 0.40, tilt: 24),
        clip: Anchor(u: 0.17, v: 0.44, tilt: -22),
        crown: [CGPoint(x: 0.14, y: 0.44), CGPoint(x: 0.30, y: 0.44), CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.70, y: 0.42), CGPoint(x: 0.86, y: 0.42)]
    )

    /// The hat sits left of the teen's crystal.
    static let pebble = PetHead(
        hat: Anchor(u: 0.40, v: 0.06, tilt: -10),
        bow: Anchor(u: 0.83, v: 0.20, tilt: 30),
        clip: Anchor(u: 0.20, v: 0.17, tilt: -26),
        crown: [CGPoint(x: 0.18, y: 0.18), CGPoint(x: 0.32, y: 0.07), CGPoint(x: 0.48, y: 0.05), CGPoint(x: 0.64, y: 0.08), CGPoint(x: 0.80, y: 0.16)]
    )
}

extension PetGeometry {
    /// Where an accessory's layers go in the drawing order.
    enum AccessoryPlace {
        /// After the body and its cheeks, before the face: the scarf, so the mouth stays on top
        /// where it rides up at small sizes.
        case underFace
        /// Over the face: everything else.
        case overFace
    }

    /// The accessory's layers for one place in the drawing order; none without one, or on an egg.
    func accessoryLayers(_ place: AccessoryPlace, reduced: Bool) -> [PetLayer] {
        guard let accessory, size > 0 else { return [] }
        if accessory == .scarf {
            return place == .underFace ? scarfLayers(reduced: reduced) : []
        }
        guard place == .overFace else { return [] }
        switch accessory {
        case .scarf: return []
        case .partyHat: return partyHatLayers(reduced: reduced)
        case .flowerCrown: return flowerCrownLayers(reduced: reduced)
        case .glasses: return glassesLayers(reduced: reduced)
        case .bow: return bowLayers(reduced: reduced)
        case .starClip: return starClipLayers(reduced: reduced)
        }
    }

    /// How big accessories are: with the stage, and a little bigger where there's no detail.
    var accessoryScale: CGFloat {
        isDetailed ? grow : grow * 1.12
    }

    /// Where things sit on this pet's head.
    var head: PetHead {
        switch species {
        case .puff:
            // The same scallops `cloudScallops` draws.
            if growth == .baby || !isDetailed {
                return .puffBaby
            }
            return growth == .teen ? .puffTeen : .puffAdult
        case .sprout:
            return .sprout
        case .ember:
            switch growth {
            case .egg, .baby: return .emberBaby
            case .teen: return .emberTeen
            case .adult, .prestige: return .emberAdult
            }
        case .pebble:
            return .pebble
        }
    }

    /// Always-On's line for an accessory.
    private var accessoryOutline: CGFloat {
        len(isDetailed ? 0.022 : 0.05)
    }

    /// A circle round a point given in points, `radius` a fraction of the square.
    private func dot(_ centre: CGPoint, radius: CGFloat) -> Path {
        let r = len(radius)
        return Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
    }

    // MARK: - Scarf

    /// A band round the body just under the mouth, wrapped to the body's outline, knotted on the
    /// right with two tails hanging down.
    private func scarfLayers(reduced: Bool) -> [PetLayer] {
        let thickness: CGFloat = isDetailed ? 0.09 * grow : 0.12
        // Under the mouth, or as low as the body allows: at small sizes it rides up a little.
        let top = min(face.mouthY + mouthUnit * 0.8 + (isDetailed ? 0.008 : 0), bodyMaxY - thickness - 0.012)
        let sag = 0.025 * grow
        let left = bodyMinX - 0.05
        let right = bodyMaxX + 0.05
        var band = Path()
        band.move(to: pt(left, top))
        band.addQuadCurve(to: pt(right, top), control: pt(0.5, top + sag * 2))
        band.addLine(to: pt(right, top + thickness))
        band.addQuadCurve(to: pt(left, top + thickness), control: pt(0.5, top + thickness + sag * 2))
        band.closeSubpath()
        let wrap = bodyPath().intersection(band)

        let knotX = bodyMinX + bodyWidth * 0.74
        let knotY = top + thickness / 2 + sag * 0.9
        let knot = ellipse(x: knotX - thickness * 0.62, y: knotY - thickness * 0.62, width: thickness * 1.24, height: thickness * 1.24)
        let bottom = min(0.985, bodyMaxY + 0.025)
        var tails = Path()
        let spec: [(offset: CGFloat, lean: CGFloat)] = [(-0.2, -0.3), (0.25, 0.55)]
        for tail in spec {
            let x = knotX + tail.offset * thickness
            let end = x + tail.lean * thickness
            tails.move(to: pt(x - thickness * 0.32, knotY))
            tails.addLine(to: pt(x + thickness * 0.32, knotY))
            tails.addLine(to: pt(end + thickness * 0.36, bottom))
            tails.addLine(to: pt(end - thickness * 0.36, bottom))
            tails.closeSubpath()
        }
        if reduced {
            let line = accessoryOutline
            return [
                PetLayer(wrap, .scarf, lineWidth: line),
                PetLayer(tails, .scarf, lineWidth: line),
                PetLayer(knot, .scarf, lineWidth: line),
            ]
        }
        return [PetLayer(wrap, .scarf), PetLayer(tails, .scarfShade), PetLayer(knot, .scarf)]
    }

    // MARK: - Party hat

    /// A cone with a pompom, leaning a little, and yellow dots where there's room for them.
    private func partyHatLayers(reduced: Bool) -> [PetLayer] {
        let anchor = head.hat
        let scale = accessoryScale
        let width = 0.25 * scale
        let pompom = 0.045 * scale
        let base = inBody(anchor.u, anchor.v)
        // Never past the top of the square: a tall flame's hat is shorter.
        let room = (base.y - pompom - 0.015) / CGFloat(cos(anchor.tilt * .pi / 180))
        let height = max(0, min(0.30 * scale, room))
        let turned = Turned(self, anchor)

        var hat = Path()
        hat.move(to: turned.at(-width / 2, 0))
        hat.addLine(to: turned.at(-width * 0.06, -height * 0.97))
        hat.addQuadCurve(to: turned.at(width * 0.06, -height * 0.97), control: turned.at(0, -height * 1.03))
        hat.addLine(to: turned.at(width / 2, 0))
        hat.addQuadCurve(to: turned.at(-width / 2, 0), control: turned.at(0, width * 0.22))
        hat.closeSubpath()
        let pom = dot(turned.at(0, -height), radius: pompom)

        if reduced {
            return [
                PetLayer(hat, .partyHat, lineWidth: accessoryOutline),
                PetLayer(pom, .hatTrim, lineWidth: accessoryOutline),
            ]
        }
        var layers = [PetLayer(hat, .partyHat)]
        if isDetailed {
            let spots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [
                (-0.12, -0.18, 0.03), (0.10, -0.32, 0.026), (-0.03, -0.55, 0.022), (0.17, -0.06, 0.02),
            ]
            var dots = Path()
            for spot in spots {
                dots.addPath(dot(turned.at(spot.x * width * 2, spot.y * height * 1.6), radius: spot.radius * scale))
            }
            layers.append(PetLayer(dots, .hatTrim))
        }
        layers.append(PetLayer(pom, .hatTrim))
        return layers
    }

    // MARK: - Flower crown

    /// Five flowers round the top of the head on a vine with leaves; at small sizes, five dots.
    private func flowerCrownLayers(reduced: Bool) -> [PetLayer] {
        let scale = accessoryScale
        let points = head.crown.map { inBody($0.x, $0.y) }
        guard let first = points.first else { return [] }
        let radius = (isDetailed ? 0.022 : 0.05) * scale

        if reduced {
            var rings = Path()
            for point in points {
                rings.addPath(circle(point.x, point.y, radius: isDetailed ? radius * 1.9 : radius))
            }
            return [PetLayer(rings, .crownPetal, lineWidth: accessoryOutline)]
        }

        var flowers = Path()
        var centres = Path()
        for (index, point) in points.enumerated() {
            guard isDetailed else {
                flowers.addPath(circle(point.x, point.y, radius: radius))
                continue
            }
            // Each flower turned a little from the last, so they don't look stamped.
            for petal in 0..<5 {
                let angle = Double(-90 + 72 * petal + 17 * index) * .pi / 180
                let x = point.x + radius * 1.1 * CGFloat(cos(angle))
                let y = point.y + radius * 1.1 * CGFloat(sin(angle))
                flowers.addPath(circle(x, y, radius: radius))
            }
            centres.addPath(circle(point.x, point.y, radius: radius * 0.75))
        }
        guard isDetailed else {
            return [PetLayer(flowers, .crownPetal)]
        }

        var vine = Path()
        var leaves = Path()
        vine.move(to: pt(first.x, first.y))
        for (a, b) in zip(points, points.dropFirst()) {
            vine.addQuadCurve(to: pt(b.x, b.y), control: pt((a.x + b.x) / 2, (a.y + b.y) / 2 - 0.01))
            // A leaf halfway, along the vine.
            let middle = pt((a.x + b.x) / 2, (a.y + b.y) / 2 - radius * 0.2)
            let angle = atan2(Double(b.y - a.y), Double(b.x - a.x))
            let leaf = Path(ellipseIn: CGRect(x: -len(radius * 0.8), y: -len(radius * 0.4), width: len(radius * 1.6), height: len(radius * 0.8)))
            let place = CGAffineTransform(rotationAngle: CGFloat(angle))
                .concatenating(CGAffineTransform(translationX: middle.x, y: middle.y))
            leaves.addPath(leaf.applying(place))
        }
        return [
            PetLayer(vine, .crownLeaf, lineWidth: len(0.012 * scale)),
            PetLayer(leaves, .crownLeaf),
            PetLayer(flowers, .crownPetal),
            PetLayer(centres, .flowerCentre),
        ]
    }

    // MARK: - Glasses

    /// Round frames over the eyes and a bridge over the nose, with a hint of glass where there's
    /// room. The frames are the face's colour, so they turn light in Always-On.
    private func glassesLayers(reduced: Bool) -> [PetLayer] {
        let face = self.face
        let radius: CGFloat
        let line: CGFloat
        if isDetailed {
            radius = min(eyeRadius * 1.9, face.eyeSpread * 0.86)
            line = featureLine * 0.8
        } else {
            radius = min(0.10, face.eyeSpread * 0.8)
            line = 0.045
        }
        var rims = Path()
        var lenses = Path()
        for side: CGFloat in [-1, 1] {
            let x = 0.5 + side * face.eyeSpread
            rims.addPath(circle(x, face.eyeY, radius: radius))
            lenses.addPath(circle(x, face.eyeY, radius: radius))
        }
        rims.addPath(arc(0.5, face.eyeY - radius * 0.1, radius: face.eyeSpread - radius, start: 200, delta: 140))
        var layers: [PetLayer] = []
        if isDetailed && !reduced {
            layers.append(PetLayer(lenses, .lens, opacity: 0.35))
        }
        layers.append(PetLayer(rims, .frames, lineWidth: len(line)))
        return layers
    }

    // MARK: - Bow

    /// Two loops and a knot on the head's right shoulder.
    private func bowLayers(reduced: Bool) -> [PetLayer] {
        let scale = accessoryScale
        let turned = Turned(self, head.bow)
        let w = 0.11 * scale
        let h = 0.085 * scale
        var loops = Path()
        for side: CGFloat in [-1, 1] {
            loops.move(to: turned.at(0, 0))
            loops.addCurve(
                to: turned.at(side * w, -h * 0.75),
                control1: turned.at(side * w * 0.35, -h * 0.9),
                control2: turned.at(side * w * 1.05, -h)
            )
            loops.addCurve(
                to: turned.at(side * w, h * 0.75),
                control1: turned.at(side * w * 1.2, -h * 0.2),
                control2: turned.at(side * w * 1.2, h * 0.6)
            )
            loops.addCurve(
                to: turned.at(0, 0),
                control1: turned.at(side * w * 0.8, h * 0.9),
                control2: turned.at(side * w * 0.35, h * 0.85)
            )
            loops.closeSubpath()
        }
        let k = 0.032 * scale
        let centre = turned.at(0, 0)
        let knot = Path(ellipseIn: CGRect(x: centre.x - len(k), y: centre.y - len(k * 1.1), width: len(k * 2), height: len(k * 2.2)))
        if reduced {
            return [
                PetLayer(loops, .bow, lineWidth: accessoryOutline),
                PetLayer(knot, .bowKnot, lineWidth: accessoryOutline),
            ]
        }
        return [PetLayer(loops, .bow), PetLayer(knot, .bowKnot)]
    }

    // MARK: - Star clip

    /// A five-pointed star clipped on the left of the head.
    private func starClipLayers(reduced: Bool) -> [PetLayer] {
        let radius = (isDetailed ? 0.09 : 0.1) * accessoryScale
        let turned = Turned(self, head.clip)
        var star = Path()
        for index in 0..<10 {
            let angle = Double(-90 + 36 * index) * .pi / 180
            let r = index.isMultiple(of: 2) ? radius : radius * 0.46
            let point = turned.at(r * CGFloat(cos(angle)), r * CGFloat(sin(angle)))
            if index == 0 {
                star.move(to: point)
            } else {
                star.addLine(to: point)
            }
        }
        star.closeSubpath()
        if reduced {
            return [PetLayer(star, .starClip, lineWidth: accessoryOutline)]
        }
        // Filled, then stroked in the same colour, which rounds its points a touch.
        return [PetLayer(star, .starClip), PetLayer(star, .starClip, lineWidth: len(radius * 0.18))]
    }
}

/// Points round an anchor on the body, turned by its tilt: `x` along and `y` down, in fractions of
/// the square. Hands back points, ready for a path.
private struct Turned {
    let geometry: PetGeometry
    /// The anchor, in fractions of the square.
    let origin: CGPoint
    let cosine: CGFloat
    let sine: CGFloat

    init(_ geometry: PetGeometry, _ anchor: PetHead.Anchor) {
        self.geometry = geometry
        origin = geometry.inBody(anchor.u, anchor.v)
        let radians = anchor.tilt * .pi / 180
        cosine = CGFloat(cos(radians))
        sine = CGFloat(sin(radians))
    }

    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        geometry.pt(origin.x + x * cosine - y * sine, origin.y + x * sine + y * cosine)
    }
}
