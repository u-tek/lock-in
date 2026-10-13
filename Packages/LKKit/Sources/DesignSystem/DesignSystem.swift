/// DesignSystem: Lockin's tokens and the handful of components the screens share.
///
/// The direction is "desk lamp at midnight": a deep indigo night, one warm lamp-amber accent,
/// SF Rounded type and monospaced countdown digits. It's designed dark-first because the surfaces
/// that sell the app are dark: the Dynamic Island, the Lock Screen at night, StandBy on a desk.
/// Light mode is the same system in daylight, with deeper inks so everything still reads.
///
/// - Colour: `LKColor` (SwiftUI colours, for views) and `LKPalette` (the same tokens as sRGB
///   numbers, for tests and the design lab). `LKMemberTone` dresses the six member states.
/// - Type: `LKFont`, and `LKTypeStyle` behind it.
/// - Metrics: `LKSpacing`, `LKRadius`, `LKMotion`.
/// - Components: `LKPrimaryButtonStyle`, `LKSecondaryButtonStyle`, `lkCard()`, `LKPill`,
///   `LKSectionHeader`, `lkGlass(in:)`, `lkScreenBackground()`, `lkNightAppearance()`.
/// - Catalogue, for the design lab: `LKPalette.groups`, `LKTypeStyle.allCases`, `LKSpacing.all`,
///   `LKRadius.all`.
///
/// The widget extension links this module, so nothing here may use extension-unavailable API
/// (`UIApplication` and friends).
public enum DesignSystem {}
