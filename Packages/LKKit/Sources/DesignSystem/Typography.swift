import SwiftUI

/// The type styles. One family, SF Rounded, for a soft and friendly voice.
///
/// Text styles scale with Dynamic Type; their `pointSize` is the size at the default text size.
/// Timers are fixed sizes, because they live in fixed spaces (the compact island, a Lock Screen
/// row), and every timer uses monospaced digits so a countdown doesn't shuffle sideways as it
/// ticks. `Text(timerInterval:countsDown:)` picks up the font like any other `Text`.
public enum LKTypeStyle: String, CaseIterable, Sendable, Identifiable {
    /// Screen titles and the first-run pitch.
    case display
    /// Section-sized titles: a sheet, a card that leads a screen.
    case title
    /// Names, row titles and button labels.
    case headline
    /// Reading text.
    case body
    /// Supporting lines under a title.
    case subheadline
    /// Small print: timestamps, counts, pills.
    case caption
    /// Section headers, in spaced capitals.
    case label
    /// The countdown on the in-app session screen.
    case timerHero
    /// Your own countdown on the Lock Screen and in StandBy.
    case timerLarge
    /// Squadmates' countdowns in the expanded island and on the Lock Screen row.
    case timer
    /// The countdown in the compact island, next to the camera.
    case timerCompact

    public var id: String { rawValue }

    /// The name shown in the design lab.
    public var name: String { rawValue }

    /// The size in points (at the default text size for styles that scale).
    public var pointSize: CGFloat {
        switch self {
        case .display: 34
        case .title: 22
        case .headline: 17
        case .body: 17
        case .subheadline: 15
        case .caption: 12
        case .label: 13
        case .timerHero: 72
        case .timerLarge: 40
        case .timer: 20
        case .timerCompact: 15
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .title: .bold
        case .headline, .label: .semibold
        case .body, .subheadline: .regular
        case .caption: .medium
        case .timerHero, .timerLarge, .timer, .timerCompact: .semibold
        }
    }

    /// The Dynamic Type style it scales with, or nil for a fixed size.
    public var textStyle: Font.TextStyle? {
        switch self {
        case .display: return .largeTitle
        case .title: return .title2
        case .headline: return .headline
        case .body: return .body
        case .subheadline: return .subheadline
        case .caption: return .caption
        case .label: return .footnote
        case .timerHero, .timerLarge, .timer, .timerCompact: return nil
        }
    }

    public var scalesWithDynamicType: Bool { textStyle != nil }

    public var isTimer: Bool {
        switch self {
        case .timerHero, .timerLarge, .timer, .timerCompact: true
        default: false
        }
    }

    /// Every digit the same width. Timers need it; so would any column of numbers.
    public var hasMonospacedDigits: Bool { isTimer }

    /// Letter spacing in points: loosened for the capitals, tightened a touch for the big title.
    public var tracking: CGFloat {
        switch self {
        case .label: 0.8
        case .display: -0.4
        default: 0
        }
    }

    public var isUppercase: Bool { self == .label }

    /// Where it's used, shown in the design lab.
    public var usage: String {
        switch self {
        case .display: "Screen titles and the first-run pitch."
        case .title: "Sheet titles and the card that leads a screen."
        case .headline: "Names, row titles, button labels."
        case .body: "Reading text."
        case .subheadline: "Supporting lines under a title."
        case .caption: "Timestamps, counts, pills."
        case .label: "Section headers, in spaced capitals (use lkType(.label))."
        case .timerHero: "The countdown on the in-app session screen."
        case .timerLarge: "Your own countdown on the Lock Screen and in StandBy."
        case .timerCompact: "The countdown in the compact island."
        case .timer: "Squadmates' countdowns in the expanded island and Lock Screen rows."
        }
    }

    /// Something to set in the style in the design lab.
    public var sample: String {
        isTimer ? "1:24:59" : "Lock in with your friends"
    }

    /// "34 pt bold, scales from Large Title" or "15 pt semibold, fixed, monospaced digits".
    public var summary: String {
        var parts = ["\(Int(pointSize)) pt \(weightName)"]
        if let textStyle {
            parts.append("scales from \(Self.name(of: textStyle))")
        } else {
            parts.append("fixed")
        }
        if hasMonospacedDigits {
            parts.append("monospaced digits")
        }
        return parts.joined(separator: ", ")
    }

    private var weightName: String {
        if weight == .bold { return "bold" }
        if weight == .semibold { return "semibold" }
        if weight == .medium { return "medium" }
        return "regular"
    }

    private static func name(of textStyle: Font.TextStyle) -> String {
        switch textStyle {
        case .largeTitle: return "Large Title"
        case .title: return "Title"
        case .title2: return "Title 2"
        case .title3: return "Title 3"
        case .headline: return "Headline"
        case .subheadline: return "Subheadline"
        case .body: return "Body"
        case .callout: return "Callout"
        case .footnote: return "Footnote"
        case .caption: return "Caption"
        case .caption2: return "Caption 2"
        default: return "a text style"
        }
    }

    public var font: Font {
        let base: Font
        if let textStyle {
            base = .system(textStyle, design: .rounded, weight: weight)
        } else {
            base = .system(size: pointSize, weight: weight, design: .rounded)
        }
        return hasMonospacedDigits ? base.monospacedDigit() : base
    }
}

/// The type styles as fonts. For the label style's tracking and caps, use `lkType(.label)`.
public enum LKFont {
    public static let display = LKTypeStyle.display.font
    public static let title = LKTypeStyle.title.font
    public static let headline = LKTypeStyle.headline.font
    public static let body = LKTypeStyle.body.font
    public static let subheadline = LKTypeStyle.subheadline.font
    public static let caption = LKTypeStyle.caption.font
    public static let label = LKTypeStyle.label.font
    public static let timerHero = LKTypeStyle.timerHero.font
    public static let timerLarge = LKTypeStyle.timerLarge.font
    public static let timer = LKTypeStyle.timer.font
    public static let timerCompact = LKTypeStyle.timerCompact.font
}

extension View {
    /// Sets text in one of the type styles, with its tracking and case.
    public func lkType(_ style: LKTypeStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}
