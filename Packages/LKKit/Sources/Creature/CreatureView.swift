import Model
import SwiftUI

/// A Lockling: a small padlock with a face, drawn from an avatar code in a pose.
///
/// Shapes only, so it's safe in the widget extension and crisp at any size. It fills a
/// `size` × `size` square and stays inside it in every pose, hats included, so it lines up in
/// rows and never pushes the island wider. Below `LocklingGeometry.detailFrom` (28) points it
/// drops hats and props and thickens its lines, which keeps it a face at 20 points.
///
/// In Always-On (`isLuminanceReduced`) the body becomes an outline and the face turns light, so
/// nothing bright glows on the dimmed Lock Screen. Nothing here animates: Live Activities ignore
/// animation, so poses differ in shape. The app is free to animate around it.
public struct CreatureView: View {
    private let avatar: AvatarCode
    private let pose: CreaturePose
    private let size: CGFloat
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(avatar: AvatarCode, pose: CreaturePose = .idle, size: CGFloat) {
        self.avatar = avatar
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        let geometry = LocklingGeometry(avatar: avatar, pose: pose, size: size)
        let layers = geometry.layers(reduced: isLuminanceReduced)
        let palette = LocklingPalette(colour: avatar.colour, pose: pose, reduced: isLuminanceReduced, geometry: geometry)
        ZStack(alignment: .topLeading) {
            ForEach(layers.indices, id: \.self) { index in
                LocklingLayerView(layer: layers[index], palette: palette)
            }
        }
        .frame(width: geometry.size, height: geometry.size, alignment: .topLeading)
        // Flattened first, so a faded Lockling (`left`) fades as one: the shackle's legs don't
        // show through its body.
        .compositingGroup()
        .opacity(palette.overallOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: pose.spokenName))
    }
}

/// One layer, filled or stroked.
private struct LocklingLayerView: View {
    let layer: LocklingLayer
    let palette: LocklingPalette

    var body: some View {
        let style = palette.style(for: layer.paint)
        let opacity = layer.opacity * palette.opacity(for: layer.paint)
        if let lineWidth = layer.lineWidth {
            layer.path
                .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .opacity(opacity)
        } else {
            layer.path
                .fill(style)
                .opacity(opacity)
        }
    }
}

/// The colours a Lockling is painted in: its own system colour for the body, a steel-grey
/// shackle, and system colours for everything it holds or wears.
struct LocklingPalette {
    /// The body's colour: the avatar's, or grey for a member who left.
    let bodyColour: Color
    let pose: CreaturePose
    let reduced: Bool
    /// The body's gradient runs over the body, not the whole frame.
    let bodyTop: CGFloat
    let bodyBottom: CGFloat
    /// The cap is blue, unless the Lockling is too.
    let capColour: Color

    init(colour: Int, pose: CreaturePose, reduced: Bool, geometry: LocklingGeometry) {
        let choice = LocklingColour(id: colour)
        bodyColour = pose == .left ? .gray : choice.color
        self.pose = pose
        self.reduced = reduced
        bodyTop = geometry.bodyMinY
        bodyBottom = geometry.bodyMaxY
        capColour = choice == .blue ? .orange : .blue
    }

    /// A member who left fades back.
    var overallOpacity: Double {
        pose == .left ? 0.55 : 1
    }

    /// Always-On dims everything but the outline, the shackle and the face, so the Lockling reads
    /// as a light line drawing.
    func opacity(for paint: LocklingPaint) -> Double {
        guard reduced else { return 1 }
        switch paint {
        case .bodyOutline, .face: return 1
        case .shackle: return 0.6
        default: return 0.5
        }
    }

    func style(for paint: LocklingPaint) -> AnyShapeStyle {
        switch paint {
        case .body:
            // A soft light from above: a touch lighter at the top, a touch deeper at the base.
            return AnyShapeStyle(LinearGradient(
                colors: [bodyColour.mix(with: .white, by: 0.14), bodyColour.mix(with: .black, by: 0.06)],
                startPoint: UnitPoint(x: 0.5, y: bodyTop),
                endPoint: UnitPoint(x: 0.5, y: bodyBottom)
            ))
        case .bodyOutline: return AnyShapeStyle(bodyColour)
        case .shackle, .muted: return AnyShapeStyle(Color.gray)
        case .shine, .catchlight, .paper, .pompom: return AnyShapeStyle(Color.white)
        // Always-On is drawn dark, so the face turns light there.
        case .face: return AnyShapeStyle(reduced ? Color.white.opacity(0.85) : Color.black.opacity(0.82))
        case .cheek, .tongue, .confettiPink, .headphonePads: return AnyShapeStyle(Color.pink)
        case .limb: return AnyShapeStyle(bodyColour.mix(with: .black, by: 0.12))
        case .sparkle, .gold: return AnyShapeStyle(Color.yellow)
        case .confettiTeal: return AnyShapeStyle(Color.teal)
        case .book, .beanie: return AnyShapeStyle(Color.red)
        case .bookSpine: return AnyShapeStyle(Color.red.mix(with: .black, by: 0.25))
        case .beanieBand: return AnyShapeStyle(Color.red.mix(with: .black, by: 0.12))
        case .mugBand: return AnyShapeStyle(Color.orange)
        case .drop: return AnyShapeStyle(Color.cyan)
        case .headphones: return AnyShapeStyle(Color.gray.mix(with: .black, by: 0.45))
        case .cap: return AnyShapeStyle(capColour)
        case .capBrim: return AnyShapeStyle(capColour.mix(with: .black, by: 0.15))
        case .petal: return AnyShapeStyle(Color.pink.mix(with: .white, by: 0.45))
        }
    }
}
