import SwiftUI

// Lockin's buttons are the system's (design/SYSTEM.md): Liquid Glass on iOS 26, bordered before
// it. Both pick up the root's tint and handle press, disabled, Dynamic Type and Increase Contrast
// themselves, which a hand-drawn style would have to redo.
//
// The two glass styles are separate types from the bordered ones, so one `ButtonStyle` value
// can't stand for either; these are view modifiers instead. They apply to every button inside
// the view, like `.buttonStyle(_:)`.
//
// For a screen's main call to action, add `.controlSize(.large)`. To fill the width, put
// `.frame(maxWidth: .infinity)` on the button's label: the style draws its background around the
// label, so a frame on the button itself doesn't stretch it. Destructive buttons take
// `role: .destructive` and the system's red.

extension View {
    /// The main action on a screen ("Lock in", "Start 25"): `.glassProminent` on iOS 26,
    /// `.borderedProminent` before. One per screen, so it's always obvious what to press.
    public func lkProminentButton() -> some View {
        modifier(LKProminentButtonModifier())
    }

    /// Every other action ("Invite", "Not now"): `.glass` on iOS 26, `.bordered` before.
    public func lkSecondaryButton() -> some View {
        modifier(LKSecondaryButtonModifier())
    }
}

struct LKProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct LKSecondaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
