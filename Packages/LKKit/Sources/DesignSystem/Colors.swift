import SwiftUI
import UIKit

/// One named system colour, for the design tokens page and the tests.
///
/// It carries the `UIColor` rather than numbers: the system owns the values, and they move with
/// the appearance, Increase Contrast and new iOS releases. The tokens page resolves it to show
/// what this phone actually draws; views use `LKColor`.
public struct LKColorToken: Hashable, Sendable, Identifiable {
    /// The token's name in this module ("focusing", "tint").
    public let name: String
    /// The UIKit colour it stands for ("systemIndigo"), so the tokens page can say what it is.
    public let uiKitName: String
    public let uiColor: UIColor
    /// Where it's used, shown on the tokens page.
    public let usage: String

    public var id: String { name }

    public init(_ name: String, uiKitName: String, uiColor: UIColor, usage: String) {
        self.name = name
        self.uiKitName = uiKitName
        self.uiColor = uiColor
        self.usage = usage
    }

    /// The colour as SwiftUI draws it, following the appearance it's drawn in. `LKColor` keeps
    /// one of each, so views should use that rather than building one in a body.
    public var color: Color {
        Color(uiColor: uiColor)
    }

    /// The value in one appearance, whatever the screen's.
    public func resolved(in scheme: ColorScheme) -> UIColor {
        uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
    }

    /// The value in one appearance as something to draw: the tokens page shows light and dark
    /// side by side, whatever the screen's own appearance.
    public func color(in scheme: ColorScheme) -> Color {
        Color(uiColor: resolved(in: scheme))
    }

    /// "#5856D6", or "#3C3C43 29%" for a translucent colour, in one appearance.
    public func hexString(in scheme: ColorScheme) -> String {
        Self.hexString(of: resolved(in: scheme))
    }

    /// True when the token looks the same in both appearances (the island's black, system grey).
    public var isFixed: Bool {
        hexString(in: .light) == hexString(in: .dark)
    }

    // Names are unique across the catalogue (CatalogueTests), so they identify a token. The colour
    // can't: several tokens share one (`done` and `petMood3` are both system green) and are still
    // different tokens.
    public static func == (lhs: LKColorToken, rhs: LKColorToken) -> Bool {
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    /// A resolved colour as hex, clamped to sRGB. A colour defined in a wider gamut can land a
    /// shade outside sRGB; the label is for people, so the nearest sRGB value is what it shows.
    static func hexString(of color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "?" }
        let hex = (byte(red) << 16) | (byte(green) << 8) | byte(blue)
        let rgb = String(format: "#%06X", hex)
        let percent = Int((min(max(alpha, 0), 1) * 100).rounded())
        return percent < 100 ? "\(rgb) \(percent)%" : rgb
    }

    private static func byte(_ component: CGFloat) -> UInt32 {
        UInt32((min(max(component, 0), 1) * 255).rounded())
    }
}

/// Tokens that belong together, for the tokens page's sections.
public struct LKColorGroup: Hashable, Sendable, Identifiable {
    public let name: String
    public let tokens: [LKColorToken]

    public var id: String { name }

    public init(_ name: String, tokens: [LKColorToken]) {
        self.name = name
        self.tokens = tokens
    }
}

/// Every colour Lockin names, each one a system colour (design/SYSTEM.md). Views use `LKColor`;
/// the tokens page and the tests use these.
///
/// The brand is one tint, indigo: the colour of Focus and Sleep in iOS, calm, and distinct from
/// the default blue. Everything else is the system's own palette, so it already adapts to light
/// and dark, Increase Contrast and the Dynamic Island, and people already know what it means.
public enum LKColorCatalogue {
    // MARK: Tint

    public static let tint = LKColorToken(
        "tint", uiKitName: "systemIndigo", uiColor: .systemIndigo,
        usage: "Set once at the root with .tint(). Buttons, links, toggles, the keyline. AccentColor matches it."
    )

    // MARK: Backgrounds

    public static let groupedBackground = LKColorToken(
        "groupedBackground", uiKitName: "systemGroupedBackground", uiColor: .systemGroupedBackground,
        usage: "Behind a screen of cards. Lists and forms draw it themselves."
    )
    public static let secondaryGroupedBackground = LKColorToken(
        "secondaryGroupedBackground", uiKitName: "secondarySystemGroupedBackground",
        uiColor: .secondarySystemGroupedBackground,
        usage: "Cards and rows on the grouped background (lkCard())."
    )
    public static let separator = LKColorToken(
        "separator", uiKitName: "separator", uiColor: .separator,
        usage: "Hairlines. Lists draw their own; this is for anything drawn by hand."
    )

    // MARK: Text

    // Views draw text with the hierarchical styles (LKColor.textPrimary is `.primary`), which
    // keep their vibrancy on materials and the Lock Screen. These are the plain label colours
    // those styles match on an opaque background, so the tokens page has something to show.

    public static let textPrimary = LKColorToken(
        "textPrimary", uiKitName: "label", uiColor: .label,
        usage: "Titles, names, body text. Draw with .primary."
    )
    public static let textSecondary = LKColorToken(
        "textSecondary", uiKitName: "secondaryLabel", uiColor: .secondaryLabel,
        usage: "Supporting text and status lines. Draw with .secondary."
    )
    public static let textTertiary = LKColorToken(
        "textTertiary", uiKitName: "tertiaryLabel", uiColor: .tertiaryLabel,
        usage: "Hints and placeholders, never anything essential. Draw with .tertiary."
    )

    // MARK: Member states

    public static let focusing = LKColorToken(
        "focusing", uiKitName: "systemIndigo", uiColor: .systemIndigo,
        usage: "Focusing. The tint: whoever's locked in wears the app's colour."
    )
    public static let onBreak = LKColorToken(
        "onBreak", uiKitName: "systemTeal", uiColor: .systemTeal,
        usage: "On a break."
    )
    public static let paused = LKColorToken(
        "paused", uiKitName: "systemOrange", uiColor: .systemOrange,
        usage: "Paused."
    )
    public static let done = LKColorToken(
        "done", uiKitName: "systemGreen", uiColor: .systemGreen,
        usage: "Finished the session."
    )
    public static let left = LKColorToken(
        "left", uiKitName: "systemGray", uiColor: .systemGray,
        usage: "Left early. The only state without a hue."
    )
    public static let slipped = LKColorToken(
        "slipped", uiKitName: "systemPink", uiColor: .systemPink,
        usage: "Slipped in Deep Focus (M8)."
    )

    // MARK: Pet mood

    public static let petMood0 = LKColorToken(
        "petMood0", uiKitName: "systemGray", uiColor: .systemGray,
        usage: "Pet mood 0, the lowest."
    )
    public static let petMood1 = LKColorToken(
        "petMood1", uiKitName: "systemOrange", uiColor: .systemOrange,
        usage: "Pet mood 1."
    )
    public static let petMood2 = LKColorToken(
        "petMood2", uiKitName: "systemMint", uiColor: .systemMint,
        usage: "Pet mood 2."
    )
    public static let petMood3 = LKColorToken(
        "petMood3", uiKitName: "systemGreen", uiColor: .systemGreen,
        usage: "Pet mood 3, the happiest."
    )

    // MARK: Live Activity

    public static let islandBackground = LKColorToken(
        "islandBackground", uiKitName: "black", uiColor: .black,
        usage: "The Dynamic Island's black, and StandBy's. Drawn only in Lab previews; the system draws the real ones."
    )

    // MARK: Catalogue

    /// The six member states in wire order (`LKMemberTone.allCases`).
    public static let memberStates: [LKColorToken] = [focusing, onBreak, paused, done, left, slipped]

    /// Pet moods 0 to 3. SPEC.md §1.5 names happy, hungry and sad without numbering them; M5
    /// decides which number is which, keeping 0 the lowest and 3 the happiest.
    public static let petMoods: [LKColorToken] = [petMood0, petMood1, petMood2, petMood3]

    /// The token for a pet mood, held to 0...3 like `ContentState.Pet.mood`.
    public static func petMood(_ mood: Int) -> LKColorToken {
        petMoods[min(max(mood, 0), petMoods.count - 1)]
    }

    /// Every token, grouped for the tokens page.
    public static let groups: [LKColorGroup] = [
        LKColorGroup("Tint", tokens: [tint]),
        LKColorGroup("Backgrounds", tokens: [groupedBackground, secondaryGroupedBackground, separator]),
        LKColorGroup("Text", tokens: [textPrimary, textSecondary, textTertiary]),
        LKColorGroup("Member states", tokens: memberStates),
        LKColorGroup("Pet mood", tokens: petMoods),
        LKColorGroup("Live Activity", tokens: [islandBackground]),
    ]

    /// Every token, in catalogue order.
    public static let all: [LKColorToken] = groups.flatMap { $0.tokens }
}

/// Lockin's colours for views: thin names over system colours, each following the appearance
/// it's drawn in. Built from `LKColorCatalogue`, so what the tokens page shows is what's drawn.
///
/// Prefer the system's own where it fits: `.tint` for the tint, `role: .destructive` for red,
/// and the backgrounds lists and forms draw for themselves.
public enum LKColor {
    /// Indigo. Set once at the root with `.tint(LKColor.tint)`; controls pick it up from there.
    public static let tint = LKColorCatalogue.tint.color

    // MARK: Backgrounds

    /// Behind a screen of `lkCard()`s: `.background(LKColor.groupedBackground)` on the scroll
    /// view. Lists and forms already draw it.
    public static let groupedBackground = LKColorCatalogue.groupedBackground.color
    /// Cards and hand-made rows on the grouped background.
    public static let secondaryGroupedBackground = LKColorCatalogue.secondaryGroupedBackground.color
    public static let separator = LKColorCatalogue.separator.color

    // MARK: Text

    // Hierarchical styles rather than label colours: on a material or the Lock Screen they pick
    // up vibrancy, which a fixed colour can't. They're shape styles, not `Color`s, so use them
    // with `foregroundStyle(_:)`; a ternary that mixes one with a `Color` needs `AnyShapeStyle`.

    public static let textPrimary: HierarchicalShapeStyle = .primary
    public static let textSecondary: HierarchicalShapeStyle = .secondary
    public static let textTertiary: HierarchicalShapeStyle = .tertiary

    // MARK: Member states

    public static let focusing = LKColorCatalogue.focusing.color
    public static let onBreak = LKColorCatalogue.onBreak.color
    public static let paused = LKColorCatalogue.paused.color
    public static let done = LKColorCatalogue.done.color
    public static let left = LKColorCatalogue.left.color
    public static let slipped = LKColorCatalogue.slipped.color

    // MARK: Pet mood

    public static let petMood0 = LKColorCatalogue.petMood0.color
    public static let petMood1 = LKColorCatalogue.petMood1.color
    public static let petMood2 = LKColorCatalogue.petMood2.color
    public static let petMood3 = LKColorCatalogue.petMood3.color

    /// The colour for a pet mood, held to 0...3.
    public static func petMood(_ mood: Int) -> Color {
        switch mood {
        case ...0: petMood0
        case 1: petMood1
        case 2: petMood2
        default: petMood3
        }
    }

    // MARK: Live Activity

    /// Black, for the Lab's stand-ins for the Dynamic Island, StandBy and Always-On. The real
    /// activity never draws a background: the Lock Screen card uses the system's default (no
    /// `activityBackgroundTint`) and the system draws the island.
    public static let islandBackground = LKColorCatalogue.islandBackground.color
}
