import SwiftUI

/// The type styles: SF Pro, the system font, through Dynamic Type (design/SYSTEM.md).
///
/// Text uses the system's text styles and their own weights, so it scales with the reader's text
/// size and sits right beside system controls. A view that needs more weight adds
/// `.fontWeight(_:)` rather than a new style. No SF Rounded: the one exception is a member's
/// monogram, which follows Contacts and sets its own font.
///
/// Every countdown has monospaced digits, so it doesn't shuffle sideways as it ticks.
/// `Text(timerInterval:countsDown:)` picks the font up like any other `Text`. Timers in the Live
/// Activity scale from a text style too; only the big ones (in-app and StandBy) are fixed sizes,
/// because they're already as large as the space allows.
///
/// The fonts leave the design unset, so the environment chooses it: nothing above them should set
/// `.fontDesign(.rounded)`.
public enum LKTypeStyle: String, CaseIterable, Sendable, Identifiable {
    // MARK: Text

    /// The first-run pitch. Screen titles come from the navigation bar, not this.
    case largeTitle
    /// A sheet's title, or the card that leads a screen.
    case title2
    /// Names and row titles.
    case headline
    /// Reading text.
    case body
    /// Supporting lines under a title.
    case subheadline
    /// Small print: explanations under a control, notes at the bottom of a section.
    case footnote
    /// Timestamps and counts.
    case caption

    // MARK: Timers

    /// The countdown on the in-app session screen, light and large like Clock's timer.
    case timerApp
    /// Your own countdown on the Lock Screen and in the Apple Watch Smart Stack.
    case timerLockScreen
    /// Your countdown in the Dynamic Island, compact and expanded.
    case timerIsland
    /// Squadmates' countdowns under their monograms: the Lock Screen row, the island's chips.
    case timerSquadmate
    /// The hero in StandBy, solo and under an hour.
    case timerStandBy
    /// StandBy when the hero won't fit: beside the squad's name, or with an hours digit.
    case timerStandBySmall

    public var id: String { rawValue }

    /// The name shown on the tokens page.
    public var name: String {
        switch self {
        case .largeTitle: "Large Title"
        case .title2: "Title 2"
        case .headline: "Headline"
        case .body: "Body"
        case .subheadline: "Subheadline"
        case .footnote: "Footnote"
        case .caption: "Caption"
        case .timerApp: "Timer, in the app"
        case .timerLockScreen: "Timer, Lock Screen"
        case .timerIsland: "Timer, Dynamic Island"
        case .timerSquadmate: "Timer, squadmate"
        case .timerStandBy: "Timer, StandBy"
        case .timerStandBySmall: "Timer, StandBy small"
        }
    }

    /// The Dynamic Type style it scales with, or nil for a fixed size.
    public var textStyle: Font.TextStyle? {
        switch self {
        case .largeTitle: .largeTitle
        case .title2, .timerLockScreen: .title2
        case .headline: .headline
        case .body, .timerIsland: .body
        case .subheadline, .timerSquadmate: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .timerApp, .timerStandBy, .timerStandBySmall: nil
        }
    }

    /// The size in points: at the default text size (Large) for styles that scale. The Live
    /// Activity reserves countdown widths from it (`Countdown.reservedWidth(fontSize:)`).
    public var pointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title2, .timerLockScreen: 22
        case .headline, .body, .timerIsland: 17
        case .subheadline, .timerSquadmate: 15
        case .footnote: 13
        case .caption: 12
        case .timerApp: 76
        case .timerStandBy: 72
        case .timerStandBySmall: 40
        }
    }

    /// A weight on top of the style's own, or nil to keep it (Headline is already semibold).
    /// Only timers add one.
    public var weight: Font.Weight? {
        switch self {
        case .timerApp: .light
        case .timerLockScreen, .timerIsland, .timerSquadmate, .timerStandBy, .timerStandBySmall: .semibold
        default: nil
        }
    }

    public var scalesWithDynamicType: Bool { textStyle != nil }

    public var isTimer: Bool {
        switch self {
        case .timerApp, .timerLockScreen, .timerIsland, .timerSquadmate, .timerStandBy, .timerStandBySmall: true
        default: false
        }
    }

    /// Every digit the same width. Timers need it; so would any column of numbers, which can add
    /// `.monospacedDigit()` to any style.
    public var hasMonospacedDigits: Bool { isTimer }

    public var font: Font {
        let base: Font
        if let textStyle {
            // A nil weight keeps the style's own.
            base = .system(textStyle, weight: weight)
        } else {
            let fixedWeight: Font.Weight = weight ?? .regular
            base = .system(size: pointSize, weight: fixedWeight)
        }
        return hasMonospacedDigits ? base.monospacedDigit() : base
    }

    /// Where it's used, shown on the tokens page.
    public var usage: String {
        switch self {
        case .largeTitle: "The first-run pitch. Screen titles come from the navigation bar."
        case .title2: "Sheet titles and the card that leads a screen."
        case .headline: "Names and row titles."
        case .body: "Reading text."
        case .subheadline: "Supporting lines under a title."
        case .footnote: "Notes under a control or at the foot of a section."
        case .caption: "Timestamps and counts."
        case .timerApp: "The countdown on the in-app session screen."
        case .timerLockScreen: "Your countdown on the Lock Screen and the Watch's Smart Stack."
        case .timerIsland: "Your countdown in the Dynamic Island."
        case .timerSquadmate: "Squadmates' countdowns under their monograms."
        case .timerStandBy: "The StandBy hero, solo and under an hour."
        case .timerStandBySmall: "StandBy beside the squad's name, or with an hours digit."
        }
    }

    /// Something to set in the style on the tokens page.
    public var sample: String {
        isTimer ? "1:24:59" : "Lock in with your friends"
    }

    /// "Large Title, 34 pt by default", "Title 2 semibold, 22 pt by default, monospaced digits"
    /// or "72 pt semibold, fixed, monospaced digits".
    public var summary: String {
        var parts: [String] = []
        if let textStyle {
            parts.append([Self.styleName(textStyle), weight.map(Self.weightName)].compactMap { $0 }.joined(separator: " "))
            parts.append("\(Int(pointSize)) pt by default")
        } else {
            parts.append("\(Int(pointSize)) pt \(Self.weightName(weight ?? .regular))")
            parts.append("fixed")
        }
        if hasMonospacedDigits {
            parts.append("monospaced digits")
        }
        return parts.joined(separator: ", ")
    }

    private static func weightName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight: "ultralight"
        case .thin: "thin"
        case .light: "light"
        case .medium: "medium"
        case .semibold: "semibold"
        case .bold: "bold"
        case .heavy: "heavy"
        case .black: "black"
        default: "regular"
        }
    }

    private static func styleName(_ textStyle: Font.TextStyle) -> String {
        switch textStyle {
        case .largeTitle: "Large Title"
        case .title: "Title"
        case .title2: "Title 2"
        case .title3: "Title 3"
        case .headline: "Headline"
        case .subheadline: "Subheadline"
        case .body: "Body"
        case .callout: "Callout"
        case .footnote: "Footnote"
        case .caption: "Caption"
        case .caption2: "Caption 2"
        default: "a text style"
        }
    }
}

/// The type styles as fonts: `.font(LKFont.headline)`. The text ones are the system's own text
/// styles under Lockin's names, so `.font(.headline)` is the same thing.
public enum LKFont {
    public static let largeTitle = LKTypeStyle.largeTitle.font
    public static let title2 = LKTypeStyle.title2.font
    public static let headline = LKTypeStyle.headline.font
    public static let body = LKTypeStyle.body.font
    public static let subheadline = LKTypeStyle.subheadline.font
    public static let footnote = LKTypeStyle.footnote.font
    public static let caption = LKTypeStyle.caption.font

    public static let timerApp = LKTypeStyle.timerApp.font
    public static let timerLockScreen = LKTypeStyle.timerLockScreen.font
    public static let timerIsland = LKTypeStyle.timerIsland.font
    public static let timerSquadmate = LKTypeStyle.timerSquadmate.font
    public static let timerStandBy = LKTypeStyle.timerStandBy.font
    public static let timerStandBySmall = LKTypeStyle.timerStandBySmall.font
}
