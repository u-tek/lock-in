import SwiftUI
import UIKit

/// One named colour with its light and dark values.
public struct LKColorToken: Hashable, Sendable, Identifiable {
    public let name: String
    public let light: RGB
    public let dark: RGB
    /// Where it's used, shown in the design lab.
    public let usage: String

    public var id: String { name }

    public init(_ name: String, light: RGB, dark: RGB, usage: String) {
        self.name = name
        self.light = light
        self.dark = dark
        self.usage = usage
    }

    /// A token that's the same in both appearances.
    public init(_ name: String, fixed: RGB, usage: String) {
        self.init(name, light: fixed, dark: fixed, usage: usage)
    }

    init(_ name: String, light: UInt32, dark: UInt32, usage: String) {
        self.init(name, light: RGB(hex: light), dark: RGB(hex: dark), usage: usage)
    }

    init(_ name: String, fixed: UInt32, usage: String) {
        self.init(name, fixed: RGB(hex: fixed), usage: usage)
    }

    /// True when the token doesn't change with the appearance.
    public var isFixed: Bool { light == dark }

    /// The value in one appearance.
    public func value(in scheme: ColorScheme) -> RGB {
        scheme == .dark ? dark : light
    }

    /// The WCAG contrast ratio of this token on `background`, both taken in `scheme`.
    public func contrastRatio(on background: LKColorToken, in scheme: ColorScheme) -> Double {
        value(in: scheme).contrastRatio(with: background.value(in: scheme))
    }

    /// A colour that follows the environment's appearance. `LKColor` keeps one of each, so views
    /// should use that rather than calling this in a body.
    public var color: Color {
        Color(light: light, dark: dark)
    }
}

/// Tokens that belong together, for the design lab's sections.
public struct LKColorGroup: Hashable, Sendable, Identifiable {
    public let name: String
    public let tokens: [LKColorToken]

    public var id: String { name }

    public init(_ name: String, tokens: [LKColorToken]) {
        self.name = name
        self.tokens = tokens
    }
}

/// Every colour token, as sRGB numbers. Views use `LKColor`; tests and the design lab use these.
///
/// The night is a deep indigo rather than neutral black, so the screen feels like a room with
/// the lights off rather than a terminal. The accent is lamp amber: the one warm light on the
/// desk, used for the main action and for anyone who's focusing.
///
/// Every member-state colour is light enough in the dark to survive Always-On dimming (checked
/// in DesignSystemTests). When `isLuminanceReduced` is true, swap large accent fills for
/// outlines or text so the dimmed Lock Screen doesn't glow.
public enum LKPalette {
    // MARK: Backgrounds

    public static let background = LKColorToken(
        "background", light: 0xF6F4FC, dark: 0x0D0B17,
        usage: "Behind every screen. Match the LaunchInk asset to it."
    )
    public static let surface = LKColorToken(
        "surface", light: 0xFFFFFF, dark: 0x17142A,
        usage: "Cards and grouped rows."
    )
    public static let surfaceRaised = LKColorToken(
        "surfaceRaised", light: 0xECE8F7, dark: 0x221E3A,
        usage: "Secondary buttons and controls sitting on a card."
    )
    public static let separator = LKColorToken(
        "separator", light: 0xDCD7EA, dark: 0x2F2A4C,
        usage: "Hairlines around cards and between rows. Decorative: never the only edge of a control."
    )

    // MARK: Text

    public static let textPrimary = LKColorToken(
        "textPrimary", light: 0x16131F, dark: 0xF4F1FF,
        usage: "Titles, names, body text."
    )
    public static let textSecondary = LKColorToken(
        "textSecondary", light: 0x565170, dark: 0xABA5C8,
        usage: "Supporting text and section headers. At least 4.5:1 on every background."
    )
    public static let textTertiary = LKColorToken(
        "textTertiary", light: 0x86829D, dark: 0x77719A,
        usage: "Hints and timestamps nobody needs to read. 3:1, so never for anything essential."
    )

    // MARK: Accent

    public static let accent = LKColorToken(
        "accent", light: 0xF5A733, dark: 0xFFB23F,
        usage: "Lamp amber. Fills: the primary button, progress, the selected chip."
    )
    public static let accentText = LKColorToken(
        "accentText", light: 0xA85500, dark: 0xFFB23F,
        usage: "Accent-coloured text and icons on a background. Deeper in light mode so it reads."
    )
    public static let onAccent = LKColorToken(
        "onAccent", fixed: 0x1E1405,
        usage: "Text and icons on an accent fill."
    )

    // MARK: Live Activity

    public static let liveActivityBackground = LKColorToken(
        "liveActivityBackground", fixed: 0x15122A,
        usage: "The Lock Screen and StandBy activity's background tint. A night window in both appearances: render the activity with lkNightAppearance()."
    )
    public static let islandBackground = LKColorToken(
        "islandBackground", fixed: 0x000000,
        usage: "The Dynamic Island's own black. Drawn only in lab previews; the system draws the real one."
    )

    // MARK: Member states

    public static let focusing = LKColorToken(
        "focusing", light: 0xA85500, dark: 0xFFB23F,
        usage: "Focusing. The accent: whoever's locked in glows lamp amber."
    )
    public static let onBreak = LKColorToken(
        "onBreak", light: 0x0A5DB5, dark: 0x5CD0FF,
        usage: "On a break. Sky blue."
    )
    public static let paused = LKColorToken(
        "paused", light: 0x50108F, dark: 0x8C7CF2,
        usage: "Paused. Violet."
    )
    public static let done = LKColorToken(
        "done", light: 0x124A28, dark: 0x9CF2BE,
        usage: "Finished the session. Mint, the brightest state in the dark."
    )
    public static let left = LKColorToken(
        "left", light: 0x6F6D7A, dark: 0xA3A0B3,
        usage: "Left early. Greyed: the only state without colour."
    )
    public static let slipped = LKColorToken(
        "slipped", light: 0x941658, dark: 0xF2575F,
        usage: "Slipped in Deep Focus (M8). Coral in the dark, raspberry in the light."
    )

    // MARK: Pet mood

    public static let petMood0 = LKColorToken(
        "petMood0", light: 0x2E3A70, dark: 0x6E80C8,
        usage: "Pet mood 0, the lowest. Dusk blue."
    )
    public static let petMood1 = LKColorToken(
        "petMood1", light: 0x784695, dark: 0xC79AE6,
        usage: "Pet mood 1. Lilac."
    )
    public static let petMood2 = LKColorToken(
        "petMood2", light: 0xA8432E, dark: 0xFFA477,
        usage: "Pet mood 2. Peach."
    )
    public static let petMood3 = LKColorToken(
        "petMood3", light: 0xA07D00, dark: 0xFFE07A,
        usage: "Pet mood 3, the happiest. Sunrise yellow."
    )

    // MARK: Catalogue

    /// The six member states in wire order (`LKMemberTone.allCases`).
    public static let memberStates: [LKColorToken] = [focusing, onBreak, paused, done, left, slipped]

    /// Pet moods 0 to 3. The ramp gets lighter and warmer as the mood improves, so it reads
    /// without relying on hue. SPEC.md §1.5 names happy, hungry and sad without numbering them;
    /// M5 decides which number is which, keeping 0 the lowest and 3 the happiest.
    public static let petMoods: [LKColorToken] = [petMood0, petMood1, petMood2, petMood3]

    /// The token for a pet mood, held to 0...3 like `ContentState.Pet.mood`.
    public static func petMood(_ mood: Int) -> LKColorToken {
        petMoods[min(max(mood, 0), petMoods.count - 1)]
    }

    /// Every token, grouped for the design lab.
    public static let groups: [LKColorGroup] = [
        LKColorGroup("Backgrounds", tokens: [background, surface, surfaceRaised, separator]),
        LKColorGroup("Text", tokens: [textPrimary, textSecondary, textTertiary]),
        LKColorGroup("Accent", tokens: [accent, accentText, onAccent]),
        LKColorGroup("Live Activity", tokens: [liveActivityBackground, islandBackground]),
        LKColorGroup("Member states", tokens: memberStates),
        LKColorGroup("Pet mood", tokens: petMoods),
    ]

    /// Every token, in catalogue order.
    public static let all: [LKColorToken] = groups.flatMap { $0.tokens }
}

/// The colour tokens as SwiftUI colours. Each follows the appearance it's drawn in; the Live
/// Activity ones are fixed.
public enum LKColor {
    public static let background = LKPalette.background.color
    public static let surface = LKPalette.surface.color
    public static let surfaceRaised = LKPalette.surfaceRaised.color
    public static let separator = LKPalette.separator.color

    public static let textPrimary = LKPalette.textPrimary.color
    public static let textSecondary = LKPalette.textSecondary.color
    public static let textTertiary = LKPalette.textTertiary.color

    public static let accent = LKPalette.accent.color
    public static let accentText = LKPalette.accentText.color
    public static let onAccent = LKPalette.onAccent.color

    public static let liveActivityBackground = LKPalette.liveActivityBackground.color
    public static let islandBackground = LKPalette.islandBackground.color

    public static let focusing = LKPalette.focusing.color
    public static let onBreak = LKPalette.onBreak.color
    public static let paused = LKPalette.paused.color
    public static let done = LKPalette.done.color
    public static let left = LKPalette.left.color
    public static let slipped = LKPalette.slipped.color

    public static let petMood0 = LKPalette.petMood0.color
    public static let petMood1 = LKPalette.petMood1.color
    public static let petMood2 = LKPalette.petMood2.color
    public static let petMood3 = LKPalette.petMood3.color

    /// The colour for a pet mood, held to 0...3.
    public static func petMood(_ mood: Int) -> Color {
        switch mood {
        case ...0: petMood0
        case 1: petMood1
        case 2: petMood2
        default: petMood3
        }
    }

    /// How strongly a tint fills a pill or a selected row behind ink text: enough to colour it,
    /// little enough that `textPrimary` stays above 4.5:1 on it (checked in DesignSystemTests).
    public static let tintedFillOpacity: Double = 0.16
}

extension Color {
    /// A fixed colour from a token value.
    public init(rgb: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    /// A colour that resolves per appearance. Fixed tokens skip the dynamic provider and stay
    /// plain values, so `activityBackgroundTint` and other places that flatten a colour early
    /// get exactly the token.
    init(light: RGB, dark: RGB) {
        if light == dark {
            self.init(rgb: light)
        } else {
            self.init(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
            })
        }
    }
}

extension UIColor {
    convenience init(rgb: RGB) {
        self.init(red: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1)
    }
}
