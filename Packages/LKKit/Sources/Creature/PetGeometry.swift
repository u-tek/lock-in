import Foundation
import Model
import SwiftUI

/// One shape of a pet, in the order it's drawn: later layers sit on top.
struct PetLayer {
    let path: Path
    let paint: PetPaint
    /// Stroked at this width with round caps and joins, or filled when nil.
    let lineWidth: CGFloat?
    let opacity: Double

    init(_ path: Path, _ paint: PetPaint, lineWidth: CGFloat? = nil, opacity: Double = 1) {
        self.path = path
        self.paint = paint
        self.lineWidth = lineWidth
        self.opacity = opacity
    }
}

/// What a layer is painted with. `PetPalette` turns these into colours.
enum PetPaint: CaseIterable, Sendable {
    case body, bodyOutline, egg, speckle, part, partOutline, partDetail, core, petal, flowerCentre
    case shine, cheek, face, catchlight, tongue, tear, muted, glow, halo, sparkle
}

/// Where everything in a squad pet sits, worked out from its species, stage, mood and size. Plain
/// shapes only, like the Lockling's (`LocklingGeometry`), so it draws in the widget extension and
/// scales from the Live Activity's pet row to the app's squad card.
///
/// Everything is a fraction of the frame (`pt`, `len`). The pet stands on the frame's floor and
/// grows up from it: a baby is about two thirds of an adult, a teen four fifths. The prestige form
/// is the adult a little smaller, in a soft halo with sparkles. Below `detailFrom` points the pet
/// keeps its silhouette and face but drops what wouldn't read (cheeks, highlights, veins, flecks,
/// the flower), thickens its lines and grows less between stages, so a baby is still a face at 18
/// points.
///
/// Mood is in the face: sad has worried brows, a frown and a tear; hungry an open "o" and a
/// rumbling tummy; content a smile; happy squeezed-shut eyes and a big open grin. The egg has no
/// face, so it shows its mood by leaning (a happy egg wobbles) and with the same tear and rumble.
///
/// The shapes were drawn and checked first in a Python prototype mirroring this file, at 18, 20,
/// 56, 64 and 160 points in every species, stage and mood, light, dark and Always-On. Nothing here
/// is animated: Live Activities ignore animation, so a wobble is a tilt.
struct PetGeometry {
    /// Below this many points the simpler drawing is used: the Live Activity's pet row.
    static let detailFrom: CGFloat = 28

    let size: CGFloat
    let isDetailed: Bool
    /// A species this version doesn't know draws as `.puff`.
    let species: PetSpecies
    let growth: PetCode.Growth
    /// 0 until adult; 1 for the first prestige form, and so on.
    let prestigeLevel: Int
    let mood: PetMood
    /// The stage's scale: 1 for an adult.
    let grow: CGFloat
    /// Where the pet stands: the bottom of its body.
    let ground: CGFloat
    /// The face's line weight.
    let featureLine: CGFloat
    let eyeRadius: CGFloat

    // The body's frame, in fractions of `size`. Leaves and crystals stand above it.
    let bodyMinX: CGFloat
    let bodyMinY: CGFloat
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat

    var bodyMaxX: CGFloat {
        bodyMinX + bodyWidth
    }

    var bodyMaxY: CGFloat {
        bodyMinY + bodyHeight
    }

    init(code: PetCode, mood: Int, size: CGFloat) {
        let size = size.isFinite ? max(0, size) : 0
        let isDetailed = size >= Self.detailFrom
        let species = PetSpecies(name: code.species)
        let growth = code.growth

        self.size = size
        self.isDetailed = isDetailed
        self.species = species
        self.growth = growth
        prestigeLevel = code.prestigeLevel
        self.mood = PetMood(level: mood)

        // Small sizes grow less between stages, so a baby is still a face in the pet row. The
        // prestige form leaves room round itself for its halo.
        let grow: CGFloat
        switch growth {
        case .egg: grow = 1
        case .baby: grow = isDetailed ? 0.62 : 0.80
        case .teen: grow = isDetailed ? 0.80 : 0.90
        case .adult: grow = 1
        case .prestige: grow = isDetailed ? 0.90 : 0.94
        }
        self.grow = grow
        let ground: CGFloat = isDetailed ? 0.95 : 0.97
        self.ground = ground
        featureLine = isDetailed ? 0.032 : 0.075
        // Eyes shrink less than the body, so the young look young.
        eyeRadius = isDetailed ? 0.05 * (0.55 + 0.45 * grow) : 0.07

        var width: CGFloat
        var height: CGFloat
        if growth == .egg {
            width = isDetailed ? 0.62 : 0.70
            height = isDetailed ? 0.80 : 0.90
        } else {
            width = species.proportions.width * grow
            height = species.proportions.height * grow
            if !isDetailed {
                // With nothing small round it, the body grows into the room, short of the edges
                // its outline needs in Always-On.
                width = min(0.9, width * 1.06)
                height = min(0.9, height * 1.06)
            }
        }
        let bottom = growth == .prestige ? ground - 0.02 : ground
        bodyWidth = width
        bodyHeight = height
        bodyMinX = 0.5 - width / 2
        bodyMinY = bottom - height
    }

    // MARK: - Units

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * size, y: y * size)
    }

    func len(_ value: CGFloat) -> CGFloat {
        value * size
    }

    /// A point in the body's frame, (0, 0) its top left and (1, 1) its bottom right, in fractions
    /// of the pet's square.
    func inBody(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: bodyMinX + u * bodyWidth, y: bodyMinY + v * bodyHeight)
    }

    /// The same point, in points.
    func bp(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let point = inBody(u, v)
        return pt(point.x, point.y)
    }

    /// An arc as its own subpath. Added to a path with an open subpath, `addRelativeArc` would
    /// join it to that subpath with a line.
    func arc(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, start: Double, delta: Double) -> Path {
        var path = Path()
        path.addRelativeArc(center: pt(x, y), radius: len(radius), startAngle: .degrees(start), delta: .degrees(delta))
        return path
    }

    func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: len(x - radius), y: len(y - radius), width: len(radius * 2), height: len(radius * 2)))
    }

    func ellipse(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: len(x), y: len(y), width: len(width), height: len(height)))
    }

    // MARK: - Layers

    /// Everything to draw, bottom first. `reduced` is Always-On: bodies become outlines, and
    /// fills, highlights, cheeks and catchlights go, so nothing glows on the dimmed Lock Screen.
    func layers(reduced: Bool) -> [PetLayer] {
        var layers: [PetLayer] = []
        if growth == .prestige {
            layers += haloLayers(reduced: reduced)
        }
        if growth == .egg {
            layers += eggLayers(reduced: reduced)
            layers += eggMoodLayers()
            return layers
        }
        layers += behindLayers(reduced: reduced)
        if reduced {
            layers.append(PetLayer(bodyPath(), .bodyOutline, lineWidth: len(isDetailed ? 0.03 : 0.07)))
        } else {
            layers.append(PetLayer(bodyPath(), .body))
        }
        layers += frontLayers(reduced: reduced)
        if isDetailed && !reduced && mood.rawValue >= PetMood.content.rawValue {
            layers.append(PetLayer(cheeks(), .cheek, opacity: 0.45))
        }
        layers += eyeLayers(reduced: reduced)
        layers += mouthLayers(reduced: reduced)
        layers += moodLayers()
        if growth == .prestige {
            layers += sparkleLayers(reduced: reduced)
        }
        return layers
    }

    // MARK: - Bodies

    func bodyPath() -> Path {
        switch species {
        case .puff: return cloud()
        case .sprout: return seed()
        case .ember: return flame()
        case .pebble: return stone()
        }
    }

    /// Where the cloud's scallops meet, round from the bottom left, in the body's frame, and each
    /// scallop's height as a fraction of the body's width. More puffs as it grows.
    private var cloudScallops: (points: [CGPoint], heights: [CGFloat]) {
        if growth == .baby || !isDetailed {
            return (
                [CGPoint(x: 0.20, y: 1.0), CGPoint(x: 0.06, y: 0.55), CGPoint(x: 0.42, y: 0.10), CGPoint(x: 0.86, y: 0.32), CGPoint(x: 0.84, y: 1.0)],
                [0.13, 0.17, 0.15, 0.15]
            )
        }
        if growth == .teen {
            return (
                [
                    CGPoint(x: 0.18, y: 1.0), CGPoint(x: 0.04, y: 0.58), CGPoint(x: 0.26, y: 0.20), CGPoint(x: 0.62, y: 0.06),
                    CGPoint(x: 0.92, y: 0.40), CGPoint(x: 0.84, y: 1.0),
                ],
                [0.12, 0.10, 0.12, 0.10, 0.12]
            )
        }
        return (
            [
                CGPoint(x: 0.16, y: 1.0), CGPoint(x: 0.03, y: 0.62), CGPoint(x: 0.17, y: 0.30), CGPoint(x: 0.42, y: 0.06),
                CGPoint(x: 0.72, y: 0.10), CGPoint(x: 0.94, y: 0.42), CGPoint(x: 0.86, y: 1.0),
            ],
            [0.11, 0.09, 0.10, 0.10, 0.09, 0.11]
        )
    }

    /// Puff: a cloud of round scallops over a nearly flat underside.
    private func cloud() -> Path {
        let scallops = cloudScallops
        let points = scallops.points.map { inBody($0.x, $0.y) }
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: pt(first.x, first.y))
        for index in 0..<(points.count - 1) where index < scallops.heights.count {
            addScallop(to: &path, from: points[index], to: points[index + 1], height: scallops.heights[index] * bodyWidth)
        }
        path.addQuadCurve(to: pt(first.x, first.y), control: pt((last.x + first.x) / 2, last.y + 0.03 * bodyHeight))
        path.closeSubpath()
        return path
    }

    /// A round bump from `a` to `b` (fractions), bulging `height` outwards: to the left of the way
    /// it's drawn, which is outwards for an outline drawn clockwise.
    private func addScallop(to path: inout Path, from a: CGPoint, to b: CGPoint, height: CGFloat) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        // A cubic whose handles both stand `reach` off the chord peaks at three quarters of it.
        let reach = height * 4 / 3
        let nx = dy / length * reach
        let ny = -dx / length * reach
        path.addCurve(to: pt(b.x, b.y), control1: pt(a.x + nx, a.y + ny), control2: pt(b.x + nx, b.y + ny))
    }

    /// Sprout: a seed sitting on the ground, round and a little wider low down, with a soft point on
    /// top where the stem comes out.
    private func seed() -> Path {
        let k: CGFloat = 0.5523
        let x0 = bodyMinX, y0 = bodyMinY, w = bodyWidth, h = bodyHeight
        let side = y0 + h * 0.6
        var path = Path()
        path.move(to: pt(0.5, y0))
        path.addCurve(to: pt(x0 + w, side), control1: pt(0.5 + w * 0.30, y0), control2: pt(x0 + w, side - h * 0.6 * 0.62))
        path.addCurve(to: pt(0.5, y0 + h), control1: pt(x0 + w, side + h * 0.4 * k), control2: pt(0.5 + w / 2 * k, y0 + h))
        path.addCurve(to: pt(x0, side), control1: pt(0.5 - w / 2 * k, y0 + h), control2: pt(x0, side + h * 0.4 * k))
        path.addCurve(to: pt(0.5, y0), control1: pt(x0, side - h * 0.6 * 0.62), control2: pt(0.5 - w * 0.30, y0))
        path.closeSubpath()
        return path
    }

    /// Ember: a plump flame on a round base, with one tip as a baby, two as a teen and three as an
    /// adult, leaning a little as if it's dancing.
    private func flame() -> Path {
        let k: CGFloat = 0.5523
        let base: CGFloat = 0.64
        let round = base + (1 - base) * k
        var path = Path()
        path.move(to: bp(0, base))
        path.addCurve(to: bp(0.5, 1), control1: bp(0, round), control2: bp(0.5 - 0.5 * k, 1))
        path.addCurve(to: bp(1, base), control1: bp(0.5 + 0.5 * k, 1), control2: bp(1, round))
        switch growth {
        case .egg, .baby:
            // The right shoulder up to the tip, then down the left.
            path.addCurve(to: bp(0.56, 0), control1: bp(1, 0.40), control2: bp(0.80, 0.18))
            path.addCurve(to: bp(0, base), control1: bp(0.34, 0.20), control2: bp(0, 0.40))
        case .teen:
            // The main tip, down into the notch, up to a smaller tip on the left.
            path.addCurve(to: bp(0.58, 0), control1: bp(1, 0.36), control2: bp(0.84, 0.16))
            path.addCurve(to: bp(0.34, 0.40), control1: bp(0.46, 0.20), control2: bp(0.40, 0.34))
            path.addCurve(to: bp(0.16, 0.30), control1: bp(0.30, 0.36), control2: bp(0.22, 0.30))
            path.addCurve(to: bp(0, base), control1: bp(0.06, 0.38), control2: bp(0, 0.48))
        case .adult, .prestige:
            // A tip on the right, the tall middle one, then a tip on the left.
            path.addCurve(to: bp(0.94, 0.18), control1: bp(1.04, 0.50), control2: bp(1.02, 0.30))
            path.addCurve(to: bp(0.72, 0.36), control1: bp(0.86, 0.26), control2: bp(0.78, 0.34))
            path.addCurve(to: bp(0.52, 0), control1: bp(0.72, 0.20), control2: bp(0.66, 0.08))
            path.addCurve(to: bp(0.32, 0.38), control1: bp(0.42, 0.10), control2: bp(0.34, 0.26))
            path.addCurve(to: bp(0.10, 0.30), control1: bp(0.26, 0.36), control2: bp(0.18, 0.34))
            path.addCurve(to: bp(0, base), control1: bp(0.04, 0.38), control2: bp(-0.01, 0.50))
        }
        path.closeSubpath()
        return path
    }

    /// The bright heart of the flame, where its face sits.
    private func flameCore() -> Path {
        let k: CGFloat = 0.5523
        let top: CGFloat = 0.38, bottom: CGFloat = 0.92, half: CGFloat = 0.34, middle: CGFloat = 0.68
        let round = middle + (bottom - middle) * k
        var path = Path()
        path.move(to: bp(0.54, top))
        path.addCurve(to: bp(0.5 + half, middle), control1: bp(0.5 + half * 0.7, top + 0.10), control2: bp(0.5 + half, middle - 0.14))
        path.addCurve(to: bp(0.5, bottom), control1: bp(0.5 + half, round), control2: bp(0.5 + half * k, bottom))
        path.addCurve(to: bp(0.5 - half, middle), control1: bp(0.5 - half * k, bottom), control2: bp(0.5 - half, round))
        path.addCurve(to: bp(0.54, top), control1: bp(0.5 - half, middle - 0.16), control2: bp(0.5 - half * 0.5, top + 0.06))
        path.closeSubpath()
        return path
    }

    /// Pebble: a smooth river stone, a little flatter on the right.
    private func stone() -> Path {
        var path = Path()
        path.move(to: bp(0.46, 0))
        path.addCurve(to: bp(1, 0.56), control1: bp(0.80, 0), control2: bp(1, 0.24))
        path.addCurve(to: bp(0.56, 1), control1: bp(1, 0.86), control2: bp(0.84, 1))
        path.addCurve(to: bp(0, 0.62), control1: bp(0.24, 1), control2: bp(0, 0.92))
        path.addCurve(to: bp(0.46, 0), control1: bp(0, 0.26), control2: bp(0.16, 0))
        path.closeSubpath()
        return path
    }

    // MARK: - What grows on it

    /// Drawn before the body, which hides where they join it: the sprout's stem and leaves, the
    /// pebble's crystals, the puff's wisp.
    private func behindLayers(reduced: Bool) -> [PetLayer] {
        var layers: [PetLayer] = []
        switch species {
        case .sprout:
            let sprout = sproutParts()
            let stemWidth = (isDetailed ? 0.035 * grow : 0.07)
            layers.append(PetLayer(sprout.stem, reduced ? .partOutline : .part, lineWidth: len(stemWidth)))
            if reduced {
                layers.append(PetLayer(sprout.leaves, .partOutline, lineWidth: len(isDetailed ? 0.03 : 0.07)))
            } else {
                layers.append(PetLayer(sprout.leaves, .part))
                if isDetailed {
                    layers.append(PetLayer(sprout.veins, .partDetail, lineWidth: len(0.014), opacity: 0.5))
                }
            }
        case .pebble:
            // A baby is a plain stone; crystals come with growing up.
            if growth != .baby {
                let crystals = crystalParts()
                if reduced {
                    layers.append(PetLayer(crystals.shards, .partOutline, lineWidth: len(isDetailed ? 0.025 : 0.06)))
                } else {
                    // Filled and then stroked in the same colour, which rounds the points a touch.
                    layers.append(PetLayer(crystals.shards, .part))
                    layers.append(PetLayer(crystals.shards, .part, lineWidth: len(0.014)))
                    if isDetailed {
                        layers.append(PetLayer(crystals.facets, .shine, opacity: 0.35))
                    }
                }
            }
        case .puff:
            // A little cloud of its own, trailing behind an adult. Its overlapping puffs would
            // show their seams as an outline, so Always-On leaves it out.
            if isDetailed && !reduced && (growth == .adult || growth == .prestige) {
                layers.append(PetLayer(wisp(), .part))
            }
        case .ember:
            break
        }
        return layers
    }

    /// Drawn over the body: the ember's bright heart, the pebble's flecks, the sprout's flower and
    /// the sheen.
    private func frontLayers(reduced: Bool) -> [PetLayer] {
        var layers: [PetLayer] = []
        if species == .ember && !reduced {
            layers.append(PetLayer(flameCore(), .core))
        }
        if species == .pebble && isDetailed && !reduced {
            layers.append(PetLayer(flecks(), .speckle, opacity: 0.5))
        }
        if species == .sprout && isDetailed && (growth == .adult || growth == .prestige) {
            let flower = self.flower()
            if reduced {
                layers.append(PetLayer(flower.petals, .partOutline, lineWidth: len(0.02)))
            } else {
                layers.append(PetLayer(flower.petals, .petal))
                layers.append(PetLayer(flower.centre, .flowerCentre))
            }
        }
        if isDetailed && !reduced {
            let spot = species.highlight
            let origin = inBody(spot.x, spot.y)
            layers.append(PetLayer(
                ellipse(x: origin.x, y: origin.y, width: spot.width * bodyWidth, height: spot.height * bodyHeight),
                .shine,
                opacity: 0.35
            ))
        }
        return layers
    }

    /// The sprout's stem, its leaves and their middle veins. Two seed leaves as a baby; a new leaf
    /// between them as a teen; two more as an adult, which also wears a flower (`flower()`).
    private func sproutParts() -> (stem: Path, leaves: Path, veins: Path) {
        let scale = isDetailed ? grow : grow * 1.06
        let stemLength: CGFloat
        switch growth {
        case .egg, .baby: stemLength = 0.07
        case .teen: stemLength = 0.10
        case .adult, .prestige: stemLength = 0.11
        }
        let height = isDetailed ? stemLength : 0.07
        let base = CGPoint(x: 0.5, y: bodyMinY + bodyHeight * 0.05)
        let top = CGPoint(x: base.x + 0.012, y: base.y - height)

        var stem = Path()
        stem.move(to: pt(base.x, base.y))
        stem.addQuadCurve(to: pt(top.x, top.y), control: pt(base.x - 0.01, base.y - height * 0.55))

        // Degrees from straight up (positive leans right), length and half-width, at an adult's scale.
        let spec: [(angle: Double, length: CGFloat, width: CGFloat)]
        if growth == .baby || !isDetailed {
            spec = [(-62, 0.17, 0.075), (62, 0.17, 0.075)]
        } else if growth == .teen {
            spec = [(-64, 0.22, 0.095), (64, 0.22, 0.095), (8, 0.13, 0.05)]
        } else {
            spec = [(-66, 0.24, 0.10), (66, 0.24, 0.10), (-16, 0.17, 0.065), (22, 0.15, 0.06)]
        }
        var leaves = Path()
        var veins = Path()
        for item in spec {
            let leaf = self.leaf(from: top, angle: item.angle, length: item.length * scale, width: item.width * scale)
            leaves.addPath(leaf.leaf)
            veins.addPath(leaf.vein)
        }
        return (stem, leaves, veins)
    }

    /// A pointed leaf from `base` (fractions), `angle` degrees from straight up, and the vein down
    /// its middle.
    private func leaf(from base: CGPoint, angle: Double, length: CGFloat, width: CGFloat) -> (leaf: Path, vein: Path) {
        let radians = angle * .pi / 180
        // Along the leaf, and across it to its right.
        let alongX = CGFloat(sin(radians)), alongY = -CGFloat(cos(radians))
        let acrossX = CGFloat(cos(radians)), acrossY = CGFloat(sin(radians))
        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            let x = base.x + alongX * length * along + acrossX * width * across
            let y = base.y + alongY * length * along + acrossY * width * across
            return pt(x, y)
        }
        var leaf = Path()
        leaf.move(to: at(0, 0))
        leaf.addCurve(to: at(1, 0), control1: at(0.25, 1), control2: at(0.75, 0.9))
        leaf.addCurve(to: at(0, 0), control1: at(0.75, -0.9), control2: at(0.25, -1))
        leaf.closeSubpath()
        var vein = Path()
        vein.move(to: at(0.18, 0))
        vein.addLine(to: at(0.72, 0))
        return (leaf, vein)
    }

    /// A five-petalled flower tucked at the top right of a grown sprout's head.
    private func flower() -> (petals: Path, centre: Path) {
        let centre = inBody(0.82, 0.2)
        let radius = 0.03 * grow
        var petals = Path()
        for index in 0..<5 {
            let angle = Double(-90 + 72 * index) * .pi / 180
            let x = centre.x + radius * 1.15 * CGFloat(cos(angle))
            let y = centre.y + radius * 1.15 * CGFloat(sin(angle))
            petals.addPath(circle(x, y, radius: radius))
        }
        return (petals, circle(centre.x, centre.y, radius: radius * 0.85))
    }

    /// Amethyst shards growing out of the pebble's top: one for a teen (and at small sizes), a
    /// cluster of three for an adult. Each facet is the shard's right half, which catches light.
    private func crystalParts() -> (shards: Path, facets: Path) {
        let scale = isDetailed ? grow : grow * 1.06
        // In the body's frame, then each shard's width and height at an adult's scale and its
        // lean in degrees.
        let spec: [(u: CGFloat, v: CGFloat, width: CGFloat, height: CGFloat, tilt: Double)]
        if growth == .teen || !isDetailed {
            spec = [(0.70, 0.10, 0.075, 0.20, 14)]
        } else {
            spec = [(0.50, 0.04, 0.08, 0.24, 4), (0.31, 0.10, 0.06, 0.15, -24), (0.68, 0.10, 0.055, 0.13, 26)]
        }
        var shards = Path()
        var facets = Path()
        for item in spec {
            let anchor = inBody(item.u, item.v)
            let w = item.width * scale
            let h = item.height * scale
            let radians = item.tilt * .pi / 180
            let cosine = CGFloat(cos(radians)), sine = CGFloat(sin(radians))
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                pt(anchor.x + x * cosine - y * sine, anchor.y + x * sine + y * cosine)
            }
            var shard = Path()
            shard.move(to: at(-w / 2, h * 0.25))
            shard.addLine(to: at(-w / 2, -h * 0.62))
            shard.addLine(to: at(0, -h))
            shard.addLine(to: at(w / 2, -h * 0.62))
            shard.addLine(to: at(w / 2, h * 0.25))
            shard.closeSubpath()
            shards.addPath(shard)

            var facet = Path()
            facet.move(to: at(0, h * 0.25))
            facet.addLine(to: at(0, -h))
            facet.addLine(to: at(w / 2, -h * 0.62))
            facet.addLine(to: at(w / 2, h * 0.25))
            facet.closeSubpath()
            facets.addPath(facet)
        }
        return (shards, facets)
    }

    /// Darker flecks in the pebble's stone.
    private func flecks() -> Path {
        let spots: [(u: CGFloat, v: CGFloat, radius: CGFloat)] = [
            (0.20, 0.42, 0.030), (0.84, 0.70, 0.026), (0.30, 0.84, 0.020), (0.72, 0.28, 0.018),
        ]
        var path = Path()
        for spot in spots {
            let centre = inBody(spot.u, spot.v)
            path.addPath(circle(centre.x, centre.y, radius: spot.radius * grow))
        }
        return path
    }

    /// The adult puff's own little cloud, over its left shoulder.
    private func wisp() -> Path {
        let x = bodyMinX + 0.02
        let y = bodyMinY + 0.02
        var path = Path()
        path.addPath(circle(x + 0.035, y - 0.005, radius: 0.035))
        path.addPath(circle(x + 0.075, y, radius: 0.028))
        path.addPath(ellipse(x: x, y: y - 0.005, width: 0.13, height: 0.045))
        return path
    }

    // MARK: - Face

    private struct Face {
        /// The eyes' centre line.
        let eyeY: CGFloat
        /// From the middle to each eye.
        let eyeSpread: CGFloat
        let mouthY: CGFloat
    }

    private var face: Face {
        let placement = species.facePlacement
        let eyeY = bodyMinY + bodyHeight * placement.eyes
        let spread = isDetailed ? bodyWidth * placement.spread : max(bodyWidth * placement.spread * 1.1, 0.15)
        let mouthY = eyeY + (isDetailed ? 0.10 * (0.6 + 0.4 * grow) : 0.15)
        return Face(eyeY: eyeY, eyeSpread: spread, mouthY: mouthY)
    }

    private func cheeks() -> Path {
        let face = self.face
        let r = eyeRadius
        var path = Path()
        for side: CGFloat in [-1, 1] {
            let x = 0.5 + side * (face.eyeSpread + r * 1.5)
            path.addPath(ellipse(x: x - r * 0.95, y: face.eyeY + r * 0.9, width: r * 1.9, height: r * 1.05))
        }
        return path
    }

    /// Happy squeezes the eyes into arcs. Hungry looks up, eyes a touch wider. Sad adds worried
    /// brows, raised in the middle.
    private func eyeLayers(reduced: Bool) -> [PetLayer] {
        let face = self.face
        let r = eyeRadius
        // A catchlight is a pixel or two below 40 points: not worth drawing.
        let catchlights = size >= 40 && !reduced
        var fills = Path()
        var strokes = Path()
        var lights = Path()
        for side: CGFloat in [-1, 1] {
            let x = 0.5 + side * face.eyeSpread
            if mood == .happy {
                strokes.addPath(arc(x, face.eyeY + r * 0.55, radius: r * 1.05, start: 200, delta: 140))
            } else {
                let y = face.eyeY - (mood == .hungry ? r * 0.25 : 0)
                let radius = r * (mood == .hungry ? 1.08 : 1)
                fills.addPath(circle(x, y, radius: radius))
                if catchlights {
                    lights.addPath(circle(x - radius * 0.32, y - radius * 0.34, radius: radius * 0.36))
                }
            }
        }
        if isDetailed && mood == .sad {
            for side: CGFloat in [-1, 1] {
                let x = 0.5 + side * face.eyeSpread
                strokes.move(to: pt(x - side * r * 1.1, face.eyeY - r * 2.1))
                strokes.addLine(to: pt(x + side * r * 1.0, face.eyeY - r * 1.5))
            }
        }
        var layers: [PetLayer] = []
        if !fills.isEmpty {
            layers.append(PetLayer(fills, .face))
        }
        if !strokes.isEmpty {
            layers.append(PetLayer(strokes, .face, lineWidth: len(featureLine)))
        }
        if !lights.isEmpty {
            layers.append(PetLayer(lights, .catchlight, opacity: 0.95))
        }
        return layers
    }

    private func mouthLayers(reduced: Bool) -> [PetLayer] {
        let y = face.mouthY
        let m: CGFloat = isDetailed ? 0.05 * (0.6 + 0.4 * grow) : 0.07
        let line = len(featureLine)
        switch mood {
        case .happy:
            // A wide open grin.
            var path = Path()
            path.move(to: pt(0.5 - m * 1.1, y - m * 0.35))
            path.addLine(to: pt(0.5 + m * 1.1, y - m * 0.35))
            path.addRelativeArc(center: pt(0.5, y - m * 0.35), radius: len(m * 1.1), startAngle: .degrees(0), delta: .degrees(180))
            path.closeSubpath()
            var layers = [PetLayer(path, .face)]
            if isDetailed && !reduced {
                layers.append(PetLayer(ellipse(x: 0.5 - m * 0.5, y: y + m * 0.2, width: m, height: m * 0.48), .tongue))
            }
            return layers
        case .content:
            return [PetLayer(arc(0.5, y - m * 0.9, radius: m * 1.2, start: 50, delta: 80), .face, lineWidth: line)]
        case .hungry:
            // An open "o", waiting for something.
            return [PetLayer(ellipse(x: 0.5 - m * 0.5, y: y - m * 0.55, width: m, height: m * 1.1), .face)]
        case .sad:
            return [PetLayer(arc(0.5, y + m * 0.75, radius: m * 1.05, start: 230, delta: 80), .face, lineWidth: line)]
        }
    }

    // MARK: - Mood extras

    /// A tear on the cheek for sad, the tummy's rumble for hungry. The tear stays at small sizes:
    /// it's what tells sad from the rest there.
    private func moodLayers() -> [PetLayer] {
        switch mood {
        case .sad:
            let face = self.face
            let r: CGFloat = isDetailed ? 0.035 : 0.06
            let x = 0.5 + face.eyeSpread + (isDetailed ? eyeRadius * 0.2 : 0)
            let y = face.eyeY + eyeRadius + r * 1.9
            return [PetLayer(tear(x, y, radius: r), .tear)]
        case .hungry:
            return isDetailed ? [rumble()] : []
        case .content, .happy:
            return []
        }
    }

    /// A drop, round at the bottom: centred on (x, y), `radius` wide.
    private func tear(_ x: CGFloat, _ y: CGFloat, radius r: CGFloat) -> Path {
        var path = Path()
        path.move(to: pt(x, y - r * 2))
        path.addQuadCurve(to: pt(x + r, y), control: pt(x + r * 0.95, y - r * 0.9))
        path.addRelativeArc(center: pt(x, y), radius: len(r), startAngle: .degrees(0), delta: .degrees(180))
        path.addQuadCurve(to: pt(x, y - r * 2), control: pt(x - r * 0.95, y - r * 0.9))
        path.closeSubpath()
        return path
    }

    /// A rumbling tummy: two short arcs beside the body, or over its shoulder when a wide body
    /// leaves no room at the side.
    private func rumble() -> PetLayer {
        let centre: CGPoint
        if bodyMaxX <= 0.84 {
            centre = CGPoint(x: bodyMaxX - 0.02, y: bodyMinY + bodyHeight * 0.7)
        } else {
            centre = CGPoint(x: 0.80, y: max(bodyMinY - 0.02, 0.12))
        }
        var path = Path()
        for radius: CGFloat in [0.05, 0.085] {
            path.addPath(arc(centre.x, centre.y, radius: radius, start: -35, delta: 70))
        }
        return PetLayer(path, .muted, lineWidth: len(0.022), opacity: 0.8)
    }

    // MARK: - Egg

    /// How far the egg leans, in degrees (negative leans left). A happy egg wobbles, a content one
    /// rocks a little, a hungry one waits upright and a sad one slumps the other way.
    var eggTilt: Double {
        switch mood {
        case .happy: -12
        case .content: -5
        case .hungry: 0
        case .sad: 6
        }
    }

    /// The lean, about the middle of the egg's base, so it stays standing on the ground.
    private var eggTransform: CGAffineTransform {
        let pivot = pt(0.5, bodyMaxY)
        let radians = eggTilt * .pi / 180
        return CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
    }

    /// An egg, widest a little below the middle.
    private func eggPath() -> Path {
        let k: CGFloat = 0.5523
        let wide: CGFloat = 0.60
        var path = Path()
        path.move(to: bp(0.5, 0))
        path.addCurve(to: bp(1, wide), control1: bp(0.5 + 0.5 * k * 0.95, 0), control2: bp(1, wide - wide * k))
        path.addCurve(to: bp(0.5, 1), control1: bp(1, wide + (1 - wide) * k), control2: bp(0.5 + 0.5 * k, 1))
        path.addCurve(to: bp(0, wide), control1: bp(0.5 - 0.5 * k, 1), control2: bp(0, wide + (1 - wide) * k))
        path.addCurve(to: bp(0.5, 0), control1: bp(0, wide - wide * k), control2: bp(0.5 - 0.5 * k * 0.95, 0))
        path.closeSubpath()
        return path
    }

    /// The egg, tinted and speckled in its species' colours: the squad can guess what's inside.
    private func eggLayers(reduced: Bool) -> [PetLayer] {
        let lean = eggTransform
        if reduced {
            return [PetLayer(eggPath().applying(lean), .bodyOutline, lineWidth: len(isDetailed ? 0.03 : 0.07))]
        }
        let spots: [(u: CGFloat, v: CGFloat, radius: CGFloat)] = isDetailed
            ? [(0.26, 0.44, 0.05), (0.62, 0.20, 0.04), (0.72, 0.52, 0.06), (0.42, 0.70, 0.045), (0.64, 0.84, 0.035)]
            : [(0.34, 0.32, 0.08), (0.68, 0.58, 0.085), (0.38, 0.74, 0.06)]
        var speckles = Path()
        for spot in spots {
            let centre = inBody(spot.u, spot.v)
            speckles.addPath(circle(centre.x, centre.y, radius: spot.radius * bodyWidth))
        }
        var layers = [
            PetLayer(eggPath().applying(lean), .egg),
            PetLayer(speckles.applying(lean), .speckle, opacity: 0.85),
        ]
        if isDetailed {
            let shine = inBody(0.22, 0.16)
            let path = ellipse(x: shine.x, y: shine.y, width: bodyWidth * 0.16, height: bodyHeight * 0.16)
            layers.append(PetLayer(path.applying(lean), .shine, opacity: 0.45))
        }
        return layers
    }

    /// Happy: motion marks either side of the wobble. Hungry: the rumble. Sad: a drop at its side.
    private func eggMoodLayers() -> [PetLayer] {
        switch mood {
        case .happy:
            var path = Path()
            let radii: [CGFloat] = isDetailed ? [0.07, 0.11] : [0.08]
            for side: CGFloat in [-1, 1] {
                let x = 0.5 + side * (bodyWidth / 2 + 0.02) - side * 0.05
                let y = bodyMinY + bodyHeight * 0.62
                for radius in radii {
                    path.addPath(arc(x, y, radius: radius, start: side > 0 ? -35 : 145, delta: 70))
                }
            }
            return [PetLayer(path, .muted, lineWidth: len(isDetailed ? 0.022 : 0.06), opacity: 0.8)]
        case .hungry:
            return isDetailed ? [rumble()] : []
        case .sad:
            let r: CGFloat = isDetailed ? 0.035 : 0.06
            return [PetLayer(tear(bodyMaxX + 0.01, bodyMinY + bodyHeight * 0.36, radius: r), .tear)]
        case .content:
            return []
        }
    }

    // MARK: - Prestige

    /// A soft glow behind the prestige form, and a fine ring round it. Always-On keeps only the
    /// ring, faintly.
    private func haloLayers(reduced: Bool) -> [PetLayer] {
        let centreY = min(bodyMinY + bodyHeight / 2, 0.53)
        let radius: CGFloat = 0.47
        var layers: [PetLayer] = []
        if !reduced {
            layers.append(PetLayer(circle(0.5, centreY, radius: radius), .glow, opacity: 0.16))
        }
        layers.append(PetLayer(
            circle(0.5, centreY, radius: radius - 0.012),
            .halo,
            lineWidth: len(isDetailed ? 0.012 : 0.03),
            opacity: reduced ? 0.35 : 0.4
        ))
        return layers
    }

    /// Sparkles round the halo: two for the first prestige form, four from the second. One at
    /// small sizes.
    private func sparkleLayers(reduced: Bool) -> [PetLayer] {
        var spots: [(x: CGFloat, y: CGFloat, radius: CGFloat)]
        if isDetailed {
            spots = [(0.13, 0.17, 0.06), (0.88, 0.30, 0.045)]
            if prestigeLevel >= 2 {
                spots += [(0.85, 0.83, 0.04), (0.09, 0.66, 0.035)]
            }
        } else {
            spots = [(0.14, 0.16, 0.10)]
        }
        var path = Path()
        for spot in spots {
            addSparkle(to: &path, x: spot.x, y: spot.y, radius: spot.radius)
        }
        return [PetLayer(path, .sparkle, opacity: reduced ? 0.5 : 1)]
    }

    /// A four-pointed sparkle: curves pulled in towards the centre.
    private func addSparkle(to path: inout Path, x: CGFloat, y: CGFloat, radius r: CGFloat) {
        let k = r * 0.18
        path.move(to: pt(x, y - r))
        path.addQuadCurve(to: pt(x + r, y), control: pt(x + k, y - k))
        path.addQuadCurve(to: pt(x, y + r), control: pt(x + k, y + k))
        path.addQuadCurve(to: pt(x - r, y), control: pt(x - k, y + k))
        path.addQuadCurve(to: pt(x, y - r), control: pt(x - k, y - k))
        path.closeSubpath()
    }
}
