import SwiftUI

/// The main action on a screen ("Lock in", "Start 25"): a lamp-amber capsule with dark text.
/// One per screen, so it's always obvious what to press.
public struct LKPrimaryButtonStyle: ButtonStyle {
    private let fillsWidth: Bool

    /// - Parameter fillsWidth: Stretch to the width offered. Off for a button that sits in a row.
    public init(fillsWidth: Bool = true) {
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        LKButtonBody(configuration: configuration, isPrimary: true, fillsWidth: fillsWidth)
    }
}

/// Every other action ("Invite", "Not now"): a raised capsule with ink text and a hairline edge.
public struct LKSecondaryButtonStyle: ButtonStyle {
    private let fillsWidth: Bool

    public init(fillsWidth: Bool = true) {
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        LKButtonBody(configuration: configuration, isPrimary: false, fillsWidth: fillsWidth)
    }
}

extension ButtonStyle where Self == LKPrimaryButtonStyle {
    /// `.buttonStyle(.lkPrimary)`
    public static var lkPrimary: LKPrimaryButtonStyle { LKPrimaryButtonStyle() }
}

extension ButtonStyle where Self == LKSecondaryButtonStyle {
    /// `.buttonStyle(.lkSecondary)`
    public static var lkSecondary: LKSecondaryButtonStyle { LKSecondaryButtonStyle() }
}

/// Both styles' look. A view rather than inline in `makeBody` so it can read the environment.
private struct LKButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(LKFont.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isPrimary ? LKColor.onAccent : LKColor.textPrimary)
            .padding(.horizontal, LKSpacing.xl)
            // 52 points: comfortably over the 44-point minimum, thumb-sized on a desk at night.
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 52)
            .background {
                Capsule().fill(isPrimary ? LKColor.accent : LKColor.surfaceRaised)
            }
            .overlay {
                if !isPrimary {
                    Capsule().strokeBorder(LKColor.separator, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            // With Reduce Motion the press shows by dimming alone.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(LKMotion.press, value: configuration.isPressed)
    }
}
