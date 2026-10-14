import Foundation
import Model
import SwiftUI

/// One shape of a Lockling, in the order it's drawn: later layers sit on top.
struct LocklingLayer {
    let path: Path
    let paint: LocklingPaint
    /// Stroked at this width with round caps and joins, or filled when nil.
    let lineWidth: CGFloat?
    let opacity: Double

    init(_ path: Path, _ paint: LocklingPaint, lineWidth: CGFloat? = nil, opacity: Double = 1) {
        self.path = path
        self.paint = paint
        self.lineWidth = lineWidth
        self.opacity = opacity
    }
}

/// What a layer is painted with. `LocklingPalette` turns these into colours.
enum LocklingPaint: CaseIterable, Sendable {
    case body, bodyOutline, shackle, shine, cheek, face, catchlight, tongue, limb, muted
    case sparkle, confettiPink, confettiTeal, paper, book, bookSpine, mugBand, drop
    case beanie, beanieBand, pompom, headphones, headphonePads, cap, capBrim, petal, gold
}

/// Where everything in a Lockling sits, worked out from its parts, pose and size. Plain shapes
/// only (paths, no images), so it draws in the widget extension, which has no network and no
/// asset budget to spare, and scales to any size.
///
/// Everything is a fraction of the frame (`pt`, `len`), so proportions hold from the island to
/// the in-app hero. Below `detailFrom` points the Lockling drops what wouldn't read (hats,
/// accessories, cheeks, the highlight), thickens its lines and grows to fill the frame.
///
/// The proportions were drawn and checked first in a Python prototype that mirrors this file, at
/// 20, 40 and 160 points in every pose and part, light, dark and Always-On; keep the two in step
/// if you change one. Nothing here is animated: Live Activities ignore animation, so poses differ
/// in shape, not motion.
struct LocklingGeometry {
    /// Below this many points the simpler drawing is used: the compact and minimal island and
    /// the expanded island's squad row.
    static let detailFrom: CGFloat = 28

    let size: CGFloat
    let isDetailed: Bool
    let body: LocklingBody
    let eyes: LocklingEyes
    /// Always `.noHat` below `detailFrom`.
    let hat: LocklingHat
    let pose: CreaturePose

    // The body's frame and the shackle, in fractions of `size`.
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat
    let cornerRadius: CGFloat
    let bodyMinX: CGFloat
    let bodyMaxX: CGFloat
    let bodyMinY: CGFloat
    let bodyMaxY: CGFloat
    /// From the middle to the centre of either leg.
    let shackleHalfWidth: CGFloat
    let shackleWidth: CGFloat
    /// From the top of the body to the top of the shackle's centre line, when closed.
    let shackleRise: CGFloat
    /// The face's line weight.
    let featureLine: CGFloat
    let lift: CGFloat
    /// Degrees; negative swings the short leg up, anticlockwise about the long one.
    let swing: CGFloat
    /// The body's scale: larger without detail, smaller under a hat.
    let grow: CGFloat

    init(avatar: AvatarCode, pose: CreaturePose, size: CGFloat) {
        let size = size.isFinite ? max(0, size) : 0
        let isDetailed = size >= Self.detailFrom
        let body = LocklingBody(id: avatar.body)
        let hat = isDetailed ? LocklingHat(id: avatar.hat) : .noHat

        self.size = size
        self.isDetailed = isDetailed
        self.body = body
        eyes = LocklingEyes(id: avatar.eyes)
        self.hat = hat
        self.pose = pose

        let proportions = body.proportions
        // Without detail there's nothing round the lock, so it grows to fill the frame. A hat
        // needs headroom, so the lock shrinks a little towards its base.
        var grow: CGFloat = isDetailed ? 1 : 1.12
        if hat != .noHat {
            grow *= 0.86
        }
        self.grow = grow
        bodyWidth = proportions.width * grow
        bodyHeight = proportions.height * grow
        cornerRadius = proportions.cornerRadius * grow
        bodyMaxY = isDetailed ? 0.95 : 0.975
        bodyMinX = 0.5 - bodyWidth / 2
        bodyMaxX = 0.5 + bodyWidth / 2
        bodyMinY = bodyMaxY - bodyHeight
        shackleHalfWidth = bodyWidth * proportions.shackleSpread
        shackleWidth = isDetailed ? 0.085 * grow : 0.125
        // Tall bodies leave less headroom: the shackle shortens rather than leave the frame.
        shackleRise = min(isDetailed ? 0.235 * grow : 0.22, bodyMinY - shackleWidth / 2 - 0.045)
        featureLine = isDetailed ? 0.034 : 0.08
        // Small sizes have no headroom for a big swing.
        let opening = CGFloat(pose.shackleOpening)
        lift = opening * (isDetailed ? 0.06 * grow : 0.02)
        swing = opening * (isDetailed ? -22 : -18)
    }

    // MARK: - Units

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * size, y: y * size)
    }

    func len(_ value: CGFloat) -> CGFloat {
        value * size
    }

    /// An arc as its own subpath. Added to a path with an open subpath, `addRelativeArc` would
    /// join it to that subpath with a line.
    func arc(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, start: CGFloat, delta: CGFloat) -> Path {
        var path = Path()
        path.addRelativeArc(
            center: pt(x, y),
            radius: len(radius),
            startAngle: .degrees(Double(start)),
            delta: .degrees(Double(delta))
        )
        return path
    }

    func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: len(x - radius), y: len(y - radius), width: len(radius * 2), height: len(radius * 2)))
    }

    func ellipse(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: len(x), y: len(y), width: len(width), height: len(height)))
    }

    /// Continuous corners, held to half the shorter side.
    func roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) -> Path {
        let corner = len(max(0, min(radius, width / 2, height / 2)))
        return Path(
            roundedRect: CGRect(x: len(x), y: len(y), width: len(width), height: len(height)),
            cornerSize: CGSize(width: corner, height: corner),
            style: .continuous
        )
    }

    // MARK: - Layers

    /// Everything to draw, bottom first. `reduced` is Always-On: the body becomes an outline, and
    /// highlights, cheeks and catchlights go, so nothing glows on the dimmed Lock Screen.
    func layers(reduced: Bool) -> [LocklingLayer] {
        var layers: [LocklingLayer] = []
        if isDetailed && pose == .celebrating {
            layers += arm(side: -1, raised: true, reduced: reduced)
            layers += arm(side: 1, raised: true, reduced: reduced)
        }
        if isDetailed && pose == .left {
            layers += arm(side: 1, raised: false, reduced: reduced)
        }
        layers.append(LocklingLayer(shackle(reduced: reduced), .shackle, lineWidth: len(shackleWidth)))
        if isDetailed && !reduced {
            layers.append(LocklingLayer(shackleShine(), .shine, lineWidth: len(shackleWidth * 0.22), opacity: 0.55))
        }
        if reduced {
            layers.append(LocklingLayer(bodyPath(), .bodyOutline, lineWidth: len(isDetailed ? 0.03 : 0.07)))
        } else {
            layers.append(LocklingLayer(bodyPath(), .body))
            if isDetailed {
                layers.append(LocklingLayer(highlight(), .shine, opacity: 0.3))
            }
        }
        if isDetailed && !reduced && pose != .left {
            layers.append(LocklingLayer(cheeks(), .cheek, opacity: 0.35))
        }
        layers += eyeLayers(reduced: reduced)
        layers += mouthLayers(reduced: reduced)
        if isDetailed {
            layers += accessoryLayers()
        }
        if pose == .slipped {
            layers += dropLayers(reduced: reduced)
        }
        if hat != .noHat {
            layers += hatLayers()
        }
        return layers
    }

    // MARK: - Body

    func bodyPath() -> Path {
        if body == .heart {
            return heart()
        }
        return roundedRect(x: bodyMinX, y: bodyMinY, width: bodyWidth, height: bodyHeight, radius: cornerRadius)
    }

    /// A love lock: lobes at the top corners and a fairly flat top between them, so the face fits.
    private func heart() -> Path {
        let x0 = bodyMinX, x1 = bodyMaxX, y0 = bodyMinY, y1 = bodyMaxY
        let w = bodyWidth, h = bodyHeight
        var path = Path()
        path.move(to: pt(0.5, y0 + h * 0.16))
        path.addCurve(to: pt(x1, y0 + h * 0.30), control1: pt(0.5 + w * 0.10, y0 - h * 0.10), control2: pt(x1 + w * 0.02, y0 - h * 0.06))
        path.addCurve(to: pt(0.5, y1), control1: pt(x1 - w * 0.02, y0 + h * 0.62), control2: pt(0.5 + w * 0.16, y1 - h * 0.10))
        path.addCurve(to: pt(x0, y0 + h * 0.30), control1: pt(0.5 - w * 0.16, y1 - h * 0.10), control2: pt(x0 + w * 0.02, y0 + h * 0.62))
        path.addCurve(to: pt(0.5, y0 + h * 0.16), control1: pt(x0 - w * 0.02, y0 - h * 0.06), control2: pt(0.5 - w * 0.10, y0 - h * 0.10))
        path.closeSubpath()
        return path
    }

    /// A soft sheen along the top, inside the body.
    private func highlight() -> Path {
        if body == .heart {
            return ellipse(x: bodyMinX + bodyWidth * 0.12, y: bodyMinY + bodyHeight * 0.08, width: bodyWidth * 0.22, height: bodyHeight * 0.12)
        }
        return roundedRect(
            x: bodyMinX + bodyWidth * 0.09,
            y: bodyMinY + bodyHeight * 0.07,
            width: bodyWidth * 0.40,
            height: bodyHeight * 0.10,
            radius: bodyHeight * 0.05
        )
    }

    // MARK: - Shackle

    /// Opening the lock: lift the shackle, then swing it about the top of its long leg. Hats ride
    /// along.
    var shackleTransform: CGAffineTransform {
        let pivot = pt(0.5 - shackleHalfWidth, bodyMinY)
        let radians = Double(swing) * .pi / 180
        return CGAffineTransform(translationX: -pivot.x, y: -pivot.y - len(lift))
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
    }

    /// The centre of the shackle's arc, before the transform.
    private var arcCentreY: CGFloat {
        bodyMinY - shackleRise + shackleHalfWidth
    }

    /// Where the short leg ends, before the transform, in fractions. Only just inside the body:
    /// its round cap points down into it, so it's hidden when closed, and a short leg swings well
    /// clear of the body when open, which is what reads as "unlocked" at 20 points.
    var shortLegTip: CGPoint {
        CGPoint(x: 0.5 + shackleHalfWidth, y: bodyMinY + shackleWidth * 0.1)
    }

    /// The shackle's centre line, stroked at `shackleWidth`. The legs run down into the body,
    /// which hides them; the long one deep enough to stay hidden when lifted. In Always-On the
    /// body is only an outline, so both stop at its edge.
    func shackle(reduced: Bool) -> Path {
        let longLeg = reduced ? bodyMinY : bodyMinY + bodyHeight * 0.35
        let shortLeg = reduced ? bodyMinY : shortLegTip.y
        var path = Path()
        path.move(to: pt(0.5 - shackleHalfWidth, longLeg))
        path.addLine(to: pt(0.5 - shackleHalfWidth, arcCentreY))
        path.addRelativeArc(center: pt(0.5, arcCentreY), radius: len(shackleHalfWidth), startAngle: .degrees(180), delta: .degrees(180))
        path.addLine(to: pt(0.5 + shackleHalfWidth, shortLeg))
        return path.applying(shackleTransform)
    }

    /// A glint on the shackle's left shoulder.
    private func shackleShine() -> Path {
        arc(0.5, arcCentreY, radius: shackleHalfWidth - shackleWidth * 0.12, start: 200, delta: 50)
            .applying(shackleTransform)
    }

    // MARK: - Face

    private struct Face {
        /// The eyes' centre line.
        let eyeY: CGFloat
        /// From the middle to each eye.
        let eyeSpread: CGFloat
        let eyeRadius: CGFloat
        let mouthY: CGFloat
    }

    private var face: Face {
        let eyeY = bodyMinY + bodyHeight * (body == .heart ? 0.40 : 0.42)
        return Face(
            eyeY: eyeY,
            eyeSpread: isDetailed ? min(0.135 * grow, bodyWidth * 0.20) : min(0.17, bodyWidth * 0.22),
            eyeRadius: isDetailed ? 0.048 * grow : 0.07,
            mouthY: eyeY + (isDetailed ? 0.115 * grow : 0.15)
        )
    }

    private func cheeks() -> Path {
        let face = self.face
        var path = Path()
        for side: CGFloat in [-1, 1] {
            let x = 0.5 + side * (face.eyeSpread + 0.065 * grow)
            let y = face.eyeY + 0.06 * grow
            path.addPath(ellipse(x: x - 0.045 * grow, y: y - 0.025 * grow, width: 0.09 * grow, height: 0.05 * grow))
        }
        return path
    }

    private enum EyeShape {
        case dot, sparkly, happy, sleepy, closed
    }

    /// The eyes the pose calls for. Most poses keep the chosen eyes; sleeping shuts them and the
    /// happy poses squeeze them into arcs.
    private func eyeShape(side: CGFloat) -> EyeShape {
        switch pose {
        case .paused: return .closed
        case .done, .celebrating: return .happy
        default: break
        }
        switch eyes {
        case .dots: return .dot
        case .happy: return .happy
        case .sleepy: return .sleepy
        case .sparkly: return .sparkly
        case .wink: return side < 0 ? .dot : .happy
        }
    }

    private func eyeLayers(reduced: Bool) -> [LocklingLayer] {
        let face = self.face
        let r = face.eyeRadius
        // Focusing looks down at the book.
        let gaze: CGFloat = pose == .focusing ? r * 0.45 : 0
        // A catchlight is a pixel or two below 40 points: not worth drawing.
        let catchlights = size >= 40 && !reduced
        var fills = Path()
        var strokes = Path()
        var lights = Path()
        for side: CGFloat in [-1, 1] {
            let x = 0.5 + side * face.eyeSpread
            let y = face.eyeY + gaze
            switch eyeShape(side: side) {
            case .dot:
                let radius = r * (pose == .slipped ? 1.15 : 1)
                fills.addPath(circle(x, y, radius: radius))
                if catchlights {
                    lights.addPath(circle(x - radius * 0.32, y - radius * 0.34, radius: radius * 0.36))
                }
            case .sparkly:
                let radius = r * 1.3
                fills.addPath(circle(x, y, radius: radius))
                if !reduced && isDetailed {
                    lights.addPath(circle(x - radius * 0.30, y - radius * 0.32, radius: radius * 0.40))
                    lights.addPath(circle(x + radius * 0.35, y + radius * 0.35, radius: radius * 0.18))
                }
            case .happy:
                strokes.addPath(arc(x, y + r * 0.55, radius: r * 1.05, start: 200, delta: 140))
            case .sleepy:
                // A heavy, level lid over the lower part of a dot.
                let radius = r * 1.05
                var lower = arc(x, y, radius: radius, start: -10, delta: 200)
                lower.closeSubpath()
                fills.addPath(lower)
                strokes.move(to: pt(x - radius * 1.3, y - radius * 0.2))
                strokes.addLine(to: pt(x + radius * 1.3, y - radius * 0.2))
            case .closed:
                strokes.addPath(arc(x, y - r * 0.45, radius: r, start: 20, delta: 140))
            }
        }
        // Worried brows, raised in the middle.
        if isDetailed && pose == .slipped {
            for side: CGFloat in [-1, 1] {
                let x = 0.5 + side * face.eyeSpread
                strokes.move(to: pt(x - side * r * 1.1, face.eyeY - r * 2.25))
                strokes.addLine(to: pt(x + side * r * 1.0, face.eyeY - r * 1.55))
            }
        }
        var layers: [LocklingLayer] = []
        if !fills.isEmpty {
            layers.append(LocklingLayer(fills, .face))
        }
        if !strokes.isEmpty {
            layers.append(LocklingLayer(strokes, .face, lineWidth: len(featureLine)))
        }
        if !lights.isEmpty {
            layers.append(LocklingLayer(lights, .catchlight, opacity: 0.95))
        }
        return layers
    }

    private func mouthLayers(reduced: Bool) -> [LocklingLayer] {
        let y = face.mouthY
        let m: CGFloat = isDetailed ? 0.055 * grow : 0.07
        let line = len(featureLine)
        switch pose {
        case .idle, .left:
            return [LocklingLayer(arc(0.5, y - m * 0.9, radius: m * 1.2, start: 50, delta: 80), .face, lineWidth: line)]
        case .onBreak:
            return [LocklingLayer(arc(0.5, y - m * 1.3, radius: m * 1.7, start: 45, delta: 90), .face, lineWidth: line)]
        case .focusing:
            var path = Path()
            path.move(to: pt(0.5 - m * 0.55, y))
            path.addLine(to: pt(0.5 + m * 0.55, y))
            return [LocklingLayer(path, .face, lineWidth: line)]
        case .paused:
            return [LocklingLayer(ellipse(x: 0.5 - m * 0.32, y: y - m * 0.3, width: m * 0.64, height: m * 0.6), .face)]
        case .done:
            // A wide open "D" of a smile.
            var path = Path()
            path.move(to: pt(0.5 - m * 1.15, y - m * 0.35))
            path.addLine(to: pt(0.5 + m * 1.15, y - m * 0.35))
            path.addRelativeArc(center: pt(0.5, y - m * 0.35), radius: len(m * 1.15), startAngle: .degrees(0), delta: .degrees(180))
            path.closeSubpath()
            var layers = [LocklingLayer(path, .face)]
            if isDetailed && !reduced {
                layers.append(LocklingLayer(ellipse(x: 0.5 - m * 0.5, y: y + m * 0.2, width: m, height: m * 0.5), .tongue))
            }
            return layers
        case .celebrating:
            var layers = [LocklingLayer(ellipse(x: 0.5 - m * 0.75, y: y - m * 0.7, width: m * 1.5, height: m * 1.6), .face)]
            if isDetailed && !reduced {
                layers.append(LocklingLayer(ellipse(x: 0.5 - m * 0.45, y: y + m * 0.3, width: m * 0.9, height: m * 0.5), .tongue))
            }
            return layers
        case .slipped:
            // A wobble.
            let half = m, rise = m * 0.28
            var path = Path()
            path.move(to: pt(0.5 - half, y + rise * 0.5))
            for step in 1...4 {
                let x = 0.5 - half + 2 * half * CGFloat(step) / 4
                path.addLine(to: pt(x, y + (step % 2 == 0 ? rise * 0.5 : -rise * 0.5)))
            }
            return [LocklingLayer(path, .face, lineWidth: line * 0.9)]
        }
    }

    // MARK: - Arms

    /// A stubby arm with a round hand. The shoulder tucks inside the body, which hides it; in
    /// Always-On the body is only an outline, so it starts at the edge.
    private func arm(side: CGFloat, raised: Bool, reduced: Bool) -> [LocklingLayer] {
        let tuck: CGFloat = reduced ? 0 : 0.05
        let shoulder: CGPoint
        let hand: CGPoint
        if raised {
            shoulder = CGPoint(x: 0.5 + side * (bodyWidth / 2 - tuck), y: bodyMinY + bodyHeight * 0.42)
            hand = CGPoint(x: 0.5 + side * min(bodyWidth / 2 + 0.075, 0.43), y: bodyMinY + 0.02)
        } else {
            shoulder = CGPoint(x: bodyMaxX - tuck, y: bodyMinY + bodyHeight * 0.45)
            hand = CGPoint(x: min(bodyMaxX + 0.06, 0.86), y: bodyMinY + 0.03)
        }
        var path = Path()
        path.move(to: pt(shoulder.x, shoulder.y))
        path.addLine(to: pt(hand.x, hand.y))
        return [
            LocklingLayer(path, .limb, lineWidth: len(0.075)),
            LocklingLayer(circle(hand.x, hand.y, radius: 0.052), .limb),
        ]
    }

    // MARK: - Accessories

    /// What the pose is holding or what floats around it. Detailed sizes only.
    private func accessoryLayers() -> [LocklingLayer] {
        switch pose {
        case .focusing:
            return book()
        case .onBreak:
            return mug()
        case .paused:
            var path = Path()
            addZ(to: &path, x: min(bodyMaxX + 0.02, 0.86), y: bodyMinY - 0.07, size: 0.085)
            addZ(to: &path, x: min(bodyMaxX + 0.10, 0.94), y: bodyMinY - 0.19, size: 0.055)
            return [LocklingLayer(path, .muted, lineWidth: len(featureLine * 0.9))]
        case .done:
            var path = Path()
            addStar(to: &path, x: 0.85, y: bodyMinY - 0.12, radius: 0.075)
            addStar(to: &path, x: 0.14, y: bodyMinY - 0.04, radius: 0.045)
            return [LocklingLayer(path, .sparkle)]
        case .celebrating:
            var stars = Path()
            addStar(to: &stars, x: 0.88, y: bodyMinY - 0.18, radius: 0.065)
            addStar(to: &stars, x: 0.10, y: bodyMinY - 0.22, radius: 0.05)
            var pink = circle(0.22, 0.10, radius: 0.022)
            pink.addPath(circle(0.94, bodyMinY + 0.02, radius: 0.018))
            let teal = circle(0.80, 0.06, radius: 0.02)
            return [
                LocklingLayer(stars, .sparkle),
                LocklingLayer(pink, .confettiPink),
                LocklingLayer(teal, .confettiTeal),
            ]
        case .left:
            // Motion lines beside the waving hand.
            let x = min(bodyMaxX + 0.06, 0.86), y = bodyMinY + 0.03
            var path = Path()
            for radius: CGFloat in [0.08, 0.115] {
                path.addPath(arc(x, y, radius: radius, start: -75, delta: 55))
            }
            return [LocklingLayer(path, .muted, lineWidth: len(featureLine * 0.8), opacity: 0.8)]
        case .idle, .slipped:
            return []
        }
    }

    private func addZ(to path: inout Path, x: CGFloat, y: CGFloat, size: CGFloat) {
        path.move(to: pt(x - size / 2, y - size / 2))
        path.addLine(to: pt(x + size / 2, y - size / 2))
        path.addLine(to: pt(x - size / 2, y + size / 2))
        path.addLine(to: pt(x + size / 2, y + size / 2))
    }

    /// A four-pointed sparkle: curves pulled in towards the centre.
    private func addStar(to path: inout Path, x: CGFloat, y: CGFloat, radius r: CGFloat) {
        let k = r * 0.18
        path.move(to: pt(x, y - r))
        path.addQuadCurve(to: pt(x + r, y), control: pt(x + k, y - k))
        path.addQuadCurve(to: pt(x, y + r), control: pt(x + k, y + k))
        path.addQuadCurve(to: pt(x - r, y), control: pt(x - k, y + k))
        path.addQuadCurve(to: pt(x, y - r), control: pt(x - k, y - k))
        path.closeSubpath()
    }

    /// An open book held up in front, seen from behind: two covers either side of the spine and
    /// the pages' edges along the top. The Lockling peeks over it.
    private func book() -> [LocklingLayer] {
        let face = self.face
        let top = face.eyeY + face.eyeRadius * 1.9
        let bottom = bodyMaxY + 0.01
        let half = min(0.205, bodyWidth * 0.30)

        var pages = Path()
        pages.move(to: pt(0.5, top))
        pages.addLine(to: pt(0.5 - half + 0.01, top + 0.02))
        pages.addLine(to: pt(0.5 - half + 0.01, top + 0.06))
        pages.addLine(to: pt(0.5, top + 0.05))
        pages.addLine(to: pt(0.5 + half - 0.01, top + 0.06))
        pages.addLine(to: pt(0.5 + half - 0.01, top + 0.02))
        pages.closeSubpath()

        var covers = Path()
        for side: CGFloat in [-1, 1] {
            covers.move(to: pt(0.5, top + 0.025))
            covers.addLine(to: pt(0.5 + side * half, top + 0.045))
            covers.addLine(to: pt(0.5 + side * half, bottom))
            covers.addLine(to: pt(0.5, bottom - 0.02))
            covers.closeSubpath()
        }

        var spine = Path()
        spine.move(to: pt(0.5, top + 0.03))
        spine.addLine(to: pt(0.5, bottom - 0.025))

        var paws = Path()
        for side: CGFloat in [-1, 1] {
            paws.addPath(circle(0.5 + side * (half + 0.005), (top + bottom) / 2 + 0.01, radius: 0.042))
        }

        // Each shape is filled and then stroked in its own colour, which rounds its corners.
        return [
            LocklingLayer(pages, .paper),
            LocklingLayer(pages, .paper, lineWidth: len(0.012)),
            LocklingLayer(covers, .book),
            LocklingLayer(covers, .book, lineWidth: len(0.025)),
            LocklingLayer(spine, .bookSpine, lineWidth: len(0.018)),
            LocklingLayer(paws, .limb),
        ]
    }

    /// A steaming mug, held at the side. The heart narrows towards its point, so the mug rides
    /// higher and further in there.
    private func mug() -> [LocklingLayer] {
        let raise: CGFloat = body == .heart ? 0.07 : 0
        let inset: CGFloat = body == .heart ? 0.05 : 0
        let x0 = min(bodyMaxX - 0.08 - inset, 0.80)
        let x1 = x0 + 0.14
        let y1 = bodyMaxY - 0.02 - raise
        let y0 = y1 - 0.15

        let handle = arc(x1, (y0 + y1) / 2, radius: 0.035, start: -80, delta: 160)
        let cup = roundedRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0, radius: 0.03)
        let band = roundedRect(x: x0, y: y0 + 0.045, width: x1 - x0, height: 0.035, radius: 0)
        var steam = Path()
        for x in [x0 + 0.04, x0 + 0.09] {
            steam.move(to: pt(x, y0 - 0.03))
            steam.addQuadCurve(to: pt(x, y0 - 0.11), control: pt(x + 0.03, y0 - 0.07))
        }
        let paw = circle(x0 + 0.005, y1 - 0.05, radius: 0.037)
        return [
            LocklingLayer(handle, .paper, lineWidth: len(0.022)),
            LocklingLayer(cup, .paper),
            LocklingLayer(band, .mugBand),
            LocklingLayer(steam, .muted, lineWidth: len(0.016), opacity: 0.7),
            LocklingLayer(paw, .limb),
        ]
    }

    /// A sweat drop at the top corner. Big enough to keep at small sizes: it's what tells
    /// slipped from focusing there.
    private func dropLayers(reduced: Bool) -> [LocklingLayer] {
        let r: CGFloat = isDetailed ? 0.04 : 0.075
        let x = bodyMaxX - (isDetailed ? 0.01 : 0.04)
        let y = bodyMinY + (isDetailed ? 0.04 : 0.06)
        var path = Path()
        path.move(to: pt(x, y - r * 2))
        path.addQuadCurve(to: pt(x + r, y), control: pt(x + r * 0.95, y - r * 0.9))
        path.addRelativeArc(center: pt(x, y), radius: len(r), startAngle: .degrees(0), delta: .degrees(180))
        path.addQuadCurve(to: pt(x, y - r * 2), control: pt(x - r * 0.95, y - r * 0.9))
        path.closeSubpath()
        var layers = [LocklingLayer(path, .drop)]
        if isDetailed && !reduced {
            layers.append(LocklingLayer(circle(x - r * 0.35, y - r * 0.1, radius: r * 0.28), .catchlight, opacity: 0.8))
        }
        return layers
    }

    // MARK: - Hats

    /// The hat, built on the closed shackle and moved with it.
    private func hatLayers() -> [LocklingLayer] {
        let g = grow
        let cy = arcCentreY
        // The shackle's outer half-width and outer top.
        let outer = shackleHalfWidth + shackleWidth / 2
        let top = cy - outer
        let move = shackleTransform
        func layer(_ path: Path, _ paint: LocklingPaint, lineWidth: CGFloat? = nil) -> LocklingLayer {
            LocklingLayer(path.applying(move), paint, lineWidth: lineWidth)
        }

        switch hat {
        case .noHat:
            return []
        case .beanie:
            let left = 0.5 - outer - 0.02 * g, right = 0.5 + outer + 0.02 * g
            let base = cy + 0.03 * g, crown = top - 0.045 * g
            let band = roundedRect(x: left - 0.012 * g, y: base - 0.035 * g, width: right - left + 0.024 * g, height: 0.06 * g, radius: 0.03 * g)
            return [
                layer(dome(left: left, right: right, base: base, crown: crown), .beanie),
                layer(band, .beanieBand),
                layer(circle(0.5, crown - 0.01 * g, radius: 0.042 * g), .pompom),
            ]
        case .headphones:
            let radius = outer + 0.035 * g
            var cups = Path()
            var pads = Path()
            for side: CGFloat in [-1, 1] {
                cups.addPath(roundedRect(x: 0.5 + side * radius - 0.04 * g, y: cy, width: 0.08 * g, height: 0.13 * g, radius: 0.04 * g))
                pads.addPath(roundedRect(x: 0.5 + side * radius - 0.022 * g, y: cy + 0.022 * g, width: 0.044 * g, height: 0.086 * g, radius: 0.022 * g))
            }
            return [
                layer(arc(0.5, cy + 0.02 * g, radius: radius, start: 180, delta: 180), .headphones, lineWidth: len(0.035 * g)),
                layer(cups, .headphones),
                layer(pads, .headphonePads),
            ]
        case .cap:
            let left = 0.5 - outer - 0.015 * g, right = 0.5 + outer + 0.015 * g
            let base = cy, crown = top - 0.025 * g
            let brim = roundedRect(x: 0.5, y: base - 0.03 * g, width: right - 0.5 + 0.14 * g, height: 0.05 * g, radius: 0.025 * g)
            return [
                layer(brim, .capBrim),
                layer(dome(left: left, right: right, base: base, crown: crown), .cap),
                layer(circle(0.5, crown + 0.005 * g, radius: 0.02 * g), .capBrim),
            ]
        case .flower:
            // Tucked in at the shackle's left shoulder.
            let angle = 225 * Double.pi / 180
            let centre = CGPoint(
                x: 0.5 + (outer - 0.005) * CGFloat(cos(angle)),
                y: cy + (outer - 0.005) * CGFloat(sin(angle))
            )
            var petals = Path()
            for index in 0..<5 {
                let t = Double(-90 + 72 * index) * Double.pi / 180
                petals.addPath(circle(
                    centre.x + 0.04 * g * CGFloat(cos(t)),
                    centre.y + 0.04 * g * CGFloat(sin(t)),
                    radius: 0.036 * g
                ))
            }
            return [
                layer(petals, .petal),
                layer(circle(centre.x, centre.y, radius: 0.027 * g), .sparkle),
            ]
        case .crown:
            let base = top + 0.03 * g, w = 0.13 * g, h = 0.14 * g
            let tips = [
                CGPoint(x: 0.5 - w - 0.01 * g, y: base - h * 0.85),
                CGPoint(x: 0.5, y: base - h),
                CGPoint(x: 0.5 + w + 0.01 * g, y: base - h * 0.85),
            ]
            var band = Path()
            band.move(to: pt(0.5 - w, base))
            band.addLine(to: pt(tips[0].x, tips[0].y))
            band.addLine(to: pt(0.5 - w * 0.45, base - h * 0.45))
            band.addLine(to: pt(tips[1].x, tips[1].y))
            band.addLine(to: pt(0.5 + w * 0.45, base - h * 0.45))
            band.addLine(to: pt(tips[2].x, tips[2].y))
            band.addLine(to: pt(0.5 + w, base))
            band.closeSubpath()
            var balls = Path()
            for tip in tips {
                balls.addPath(circle(tip.x, tip.y - 0.012 * g, radius: 0.02 * g))
            }
            return [
                layer(band, .gold),
                layer(band, .gold, lineWidth: len(0.02 * g)),
                layer(balls, .gold),
                layer(circle(0.5, base - h * 0.32, radius: 0.022 * g), .confettiPink),
            ]
        }
    }

    /// Half an ellipse standing on `base`, from `left` to `right`, `crown` at the top.
    private func dome(left: CGFloat, right: CGFloat, base: CGFloat, crown: CGFloat) -> Path {
        // The cubic handle that draws a quarter ellipse.
        let k: CGFloat = 0.5523
        let rx = (right - left) / 2, ry = base - crown
        var path = Path()
        path.move(to: pt(left, base))
        path.addCurve(to: pt(0.5, crown), control1: pt(left, base - ry * k), control2: pt(0.5 - rx * k, crown))
        path.addCurve(to: pt(right, base), control1: pt(0.5 + rx * k, crown), control2: pt(right, base - ry * k))
        path.closeSubpath()
        return path
    }
}
