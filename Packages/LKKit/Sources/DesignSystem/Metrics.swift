import SwiftUI

/// A named number, for the design lab's tables.
public struct LKMetricToken: Hashable, Sendable, Identifiable {
    public let name: String
    public let value: CGFloat

    public var id: String { name }

    public init(_ name: String, _ value: CGFloat) {
        self.name = name
        self.value = value
    }
}

/// Spacing, on a 4-point grid with one half step.
public enum LKSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48

    /// Screen edges. 16 rather than 20 so a squad row still fits on a 375-point iPhone SE.
    public static let gutter: CGFloat = 16
    /// Inside cards.
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

/// Corner radii. Always drawn with `.continuous` corners. Buttons and pills are capsules, so they
/// have no radius here.
public enum LKRadius {
    /// Small marks: badges, swatches, the creature's frame in a row.
    public static let small: CGFloat = 8
    /// Inner panels and inputs on a card.
    public static let medium: CGFloat = 14
    /// Cards.
    public static let card: CGFloat = 22
    /// Sheets and the session screen's hero panel.
    public static let large: CGFloat = 32

    public static let all: [LKMetricToken] = [
        LKMetricToken("small", small),
        LKMetricToken("medium", medium),
        LKMetricToken("card", card),
        LKMetricToken("large", large),
    ]
}

/// Named motion for the app. Live Activities ignore animation modifiers (only content
/// transitions animate there, and nothing animates in Always-On), so none of this applies to the
/// widget extension.
public enum LKMotion {
    /// Buttons and chips answering a touch.
    public static var press: Animation { .spring(response: 0.28, dampingFraction: 0.8) }
    /// Most state changes: settles without a bounce.
    public static var settle: Animation { .spring(response: 0.5, dampingFraction: 0.88) }
    /// Something worth a little bounce: a finished session, a cheer arriving.
    public static var celebrate: Animation { .spring(response: 0.55, dampingFraction: 0.62) }
}
