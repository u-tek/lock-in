/// DesignSystem: Lockin's names for the system's design, and the few pieces the system doesn't
/// provide. The contract is design/SYSTEM.md; this module follows it.
///
/// The direction is native Apple: an app Apple could have shipped in iOS 26. System colours that
/// follow light and dark mode, SF Pro through Dynamic Type, the standard containers and controls
/// (`NavigationStack`, inset-grouped `List`, `Form`, `LabeledContent`, the system button styles),
/// and Liquid Glass wherever the system provides it. The brand lives in one tint, indigo, in the
/// creatures (M1) and in the Live Activity, not in custom chrome. When in doubt, do what
/// Settings, Fitness, Clock and the Focus screens do. (This replaced the first "desk lamp at
/// midnight" palette: amber on deep indigo, dark-first, SF Rounded everywhere.)
///
/// - Colour: `LKColor`, thin names over system colours for views; `LKColorCatalogue`, the same
///   colours as `LKColorToken`s carrying their `UIColor`, for the tokens page and the tests.
///   `LKMemberTone` dresses the six member states.
/// - Type: `LKFont`, and `LKTypeStyle` behind it: Dynamic Type text styles, and monospaced-digit
///   timers for the app, the Lock Screen, the Dynamic Island and StandBy.
/// - Metrics: `LKSpacing` (4-point grid), `LKRadius`, `LKMotion` (the system's springs).
/// - Components: `LKIconTile` (a Settings-style row icon), `lkProminentButton()` and
///   `lkSecondaryButton()` (the system's glass or bordered styles), `lkCard()` and
///   `lkMaterialCard()` for the few things that can't be a list row.
///
/// What's not here, on purpose: screen backgrounds (lists and forms draw them), section headers
/// (`Section`'s own), custom button styles, blurs and shadows.
///
/// The widget extension links this module, so nothing here may use extension-unavailable API
/// (`UIApplication` and friends). `UIColor` and `UITraitCollection` are fine.
public enum DesignSystem {}
