import SwiftUI

/// A Settings-style row icon: a white SF Symbol on a rounded square filled with a system colour.
///
/// Use it as a row's icon so a list reads like Settings:
///
///     Label { Text("Notifications") } icon: { LKIconTile(systemName: "bell.fill", color: .red) }
///
/// It grows with Dynamic Type alongside the row's text, as Settings' icons do. It's decorative,
/// hidden from VoiceOver: the row's title says what it is.
public struct LKIconTile: View {
    /// Settings' icon size at the default text size.
    public nonisolated static let defaultSize: CGFloat = 29

    /// Corner radius as a share of the side. Settings' row icons are small app icons, so they
    /// share the app icon's proportion (about 6.5 points on a 29-point tile) rather than a fixed
    /// radius, which would look rounder as Dynamic Type grows the tile.
    nonisolated static let cornerFraction: CGFloat = 0.225

    /// The symbol's point size as a share of the side: a 29-point tile carries a 17-point symbol,
    /// leaving room for wide ones like `hand.wave.fill`.
    nonisolated static let symbolFraction: CGFloat = 0.6

    private let systemName: String
    private let color: Color
    @ScaledMetric private var size: CGFloat

    /// - Parameters:
    ///   - systemName: An SF Symbol. Filled variants read best at this size.
    ///   - color: The fill: a system colour, or a member tone's `color`.
    ///   - size: The side at the default text size; it scales with the body text style.
    public init(systemName: String, color: Color, size: CGFloat = LKIconTile.defaultSize) {
        self.systemName = systemName
        self.color = color
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * Self.symbolFraction, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * Self.cornerFraction, style: .continuous))
            .accessibilityHidden(true)
    }
}
