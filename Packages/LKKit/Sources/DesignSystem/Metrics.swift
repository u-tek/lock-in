import SwiftUI

/// A named number, for the tokens page's tables.
public struct LKMetricToken: Hashable, Sendable, Identifiable {
    public let name: String
    public let value: CGFloat

    public var id: String { name }

    public init(_ name: String, _ value: CGFloat) {
        self.name = name
        self.value = value
    }
}

/// Spacing on a 4-point grid, for layouts drawn by hand. Lists, forms and navigation bars bring
/// their own margins and row spacing; don't add these on top of them.
public enum LKSpacing {
    /// The one half step: between a title and the line under it, where 4 looks loose.
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48

    /// Screen edges for content outside a list: the inset-grouped list's own side margin on
    /// iPhones up to the Pro, so hand-laid cards line up with list sections on the same screen.
    public static let gutter: CGFloat = 16
    /// Inside cards, matching a list row's insets.
    public static let cardPadding: CGFloat = 16

    public static let all: [LKMetricToken] = [
        LKMetricToken("xxs", xxs),
        LKMetricToken("xs", xs),
        LKMetricToken("s", s),
        LKMetricToken("m", m),
        LKMetricToken("l", l),
        LKMetricToken("xl", xl),
        LKMetricToken("xxl", xxl),
        LKMetricToken("xxxl", xxxl),
        LKMetricToken("gutter", gutter),
        LKMetricToken("cardPadding", cardPadding),
    ]
}

/// Corner radii, always drawn with `.continuous` corners. Let containers choose where they can:
/// lists, sheets, buttons and the Live Activity's own card all bring their own. These are for
/// shapes drawn by hand. `LKIconTile` works its corner out from its size.
public enum LKRadius {
    /// Small marks: colour swatches, a creature's frame in a row.
    public static let small: CGFloat = 8
    /// Panels inside a card.
    public static let medium: CGFloat = 16
    /// Cards drawn by hand (`lkCard()`), and the Lab's stand-in for the Lock Screen card. The
    /// same corner as a Live Activity on the Lock Screen.
    public static let card: CGFloat = 26

    public static let all: [LKMetricToken] = [
        LKMetricToken("small", small),
        LKMetricToken("medium", medium),
        LKMetricToken("card", card),
    ]
}

/// The system's own springs under Lockin's names, for the app. Live Activities ignore animation
/// modifiers (only content transitions animate there, and nothing animates in Always-On), so none
/// of this applies to the widget extension. System controls animate themselves; these are for
/// Lockin's own views.
public enum LKMotion {
    /// Something answering a touch: quick, no overshoot to speak of.
    public static var press: Animation { .snappy }
    /// Most state changes: settles without a bounce.
    public static var settle: Animation { .smooth }
    /// Something worth a little bounce: a finished session, a cheer arriving.
    public static var celebrate: Animation { .bouncy }
}
