import Model
import SwiftUI

/// The squad's pet (SPEC.md §1.5): the egg, then a puff, sprout, ember or pebble at baby, teen and
/// adult, and the adult in a halo for the prestige forms, with its mood in its face.
///
/// Shapes only, like the Lockling (`CreatureView`), so it's safe in the widget extension and the
/// Live Activity, and crisp at any size. It fills a `size` × `size` square, standing on the
/// bottom, and stays inside it at every stage, so a growing pet never pushes a row about. Below
/// `PetGeometry.detailFrom` (28) points it keeps its shape and face and drops the small things,
/// which keeps it readable in the Live Activity's pet row.
///
/// In Always-On (`isLuminanceReduced`) it becomes an outline with a light face, so nothing bright
/// glows on the dimmed Lock Screen. Nothing here animates: Live Activities ignore animation, so
/// moods and stages differ in shape, and the happy egg's wobble is a tilt. A species this version
/// doesn't know draws as a puff.
public struct PetView: View {
    private let code: PetCode
    private let mood: Int
    private let size: CGFloat
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// - Parameters:
    ///   - code: Species and stage, as in `Pet.k`.
    ///   - mood: 0 sad, 1 hungry, 2 content, 3 happy (`PetMood`); held to that range.
    ///   - size: The square it fills, in points.
    public init(code: PetCode, mood: Int, size: CGFloat) {
        self.code = code
        self.mood = mood
        self.size = size
    }

    public var body: some View {
        let geometry = PetGeometry(code: code, mood: mood, size: size)
        let layers = geometry.layers(reduced: isLuminanceReduced)
        let palette = PetPalette(species: geometry.species, reduced: isLuminanceReduced, geometry: geometry)
        ZStack(alignment: .topLeading) {
            ForEach(layers.indices, id: \.self) { index in
                PetLayerView(layer: layers[index], palette: palette)
            }
        }
        .frame(width: geometry.size, height: geometry.size, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.accessibilityLabel(code: code, mood: mood)))
    }

    /// What VoiceOver says for the pet on its own: "Squad pet, teen sprout, happy". An egg doesn't
    /// give its species away (docs/milestones/M5.md: it's revealed at hatching), and a species this
    /// version doesn't know is named as what's drawn, a puff. English only until the app has a
    /// string catalogue.
    public static func accessibilityLabel(code: PetCode, mood: Int) -> String {
        let feeling = PetMood(level: mood).name
        guard code.growth != .egg else {
            return "Squad pet, egg, \(feeling)"
        }
        let species = PetSpecies(name: code.species)
        return "Squad pet, \(code.stageName) \(species.rawValue), \(feeling)"
    }
}

/// One layer, filled or stroked.
private struct PetLayerView: View {
    let layer: PetLayer
    let palette: PetPalette

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

/// The colours a pet is painted in: its species' system colours for the body and what grows on it,
/// and system colours for its face, cheeks, tear and sparkles, as the Lockling's are.
struct PetPalette {
    let species: PetSpecies
    let reduced: Bool
    /// The body's gradient runs over the body, not the whole frame.
    let bodyTop: CGFloat
    let bodyBottom: CGFloat

    init(species: PetSpecies, reduced: Bool, geometry: PetGeometry) {
        self.species = species
        self.reduced = reduced
        bodyTop = geometry.bodyMinY
        bodyBottom = geometry.bodyMaxY
    }

    /// Always-On dims everything but the outlines, the face and the faint halo, so the pet reads as
    /// a light line drawing.
    func opacity(for paint: PetPaint) -> Double {
        guard reduced else { return 1 }
        switch paint {
        case .bodyOutline, .partOutline, .face, .halo, .sparkle: return 1
        default: return 0.5
        }
    }

    func style(for paint: PetPaint) -> AnyShapeStyle {
        switch paint {
        case .body:
            // A soft light from above, as on the Lockling.
            let colour = species.bodyColour
            return AnyShapeStyle(LinearGradient(
                colors: [colour.mix(with: .white, by: 0.14), colour.mix(with: .black, by: 0.06)],
                startPoint: UnitPoint(x: 0.5, y: bodyTop),
                endPoint: UnitPoint(x: 0.5, y: bodyBottom)
            ))
        case .bodyOutline: return AnyShapeStyle(species.bodyColour)
        // The egg is paler than what hatches from it.
        case .egg: return AnyShapeStyle(species.bodyColour.mix(with: .white, by: 0.35))
        case .speckle: return AnyShapeStyle(species.speckleColour)
        case .part, .partOutline: return AnyShapeStyle(species.partColour)
        case .partDetail: return AnyShapeStyle(species.partColour.mix(with: .black, by: 0.3))
        case .core: return AnyShapeStyle(Color.yellow)
        case .petal: return AnyShapeStyle(Color.pink.mix(with: .white, by: 0.4))
        case .flowerCentre, .glow, .halo, .sparkle: return AnyShapeStyle(Color.yellow)
        case .shine, .catchlight: return AnyShapeStyle(Color.white)
        // Always-On is drawn dark, so the face turns light there.
        case .face: return AnyShapeStyle(reduced ? Color.white.opacity(0.85) : Color.black.opacity(0.82))
        // Lighter than the Lockling's, so it stays pink on the green and grey pets.
        case .cheek: return AnyShapeStyle(Color.pink.mix(with: .white, by: 0.3))
        case .tongue: return AnyShapeStyle(Color.pink)
        case .tear: return AnyShapeStyle(Color.cyan)
        case .muted: return AnyShapeStyle(Color.gray)
        }
    }
}
