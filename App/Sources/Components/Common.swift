import DesignSystem
import Model
import Paywall
import SwiftUI

/// The symbols that mean the same thing everywhere in the app.
enum LockinSymbol {
    static let coin = "circle.hexagonpath.fill"
    static let plus = "crown.fill"
}

/// Plus's crown colour, and the coins'. System colours, like everything else.
enum LockinColour {
    static let plus = Color.orange
    static let coin = Color.yellow
}

extension View {
    /// Lockin Plus's paywall as a sheet.
    func lockinPaywall(isPresented: Binding<Bool>, store: PlusStore, avatar: AvatarCode) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(store: store, avatar: avatar) {
                isPresented.wrappedValue = false
            }
        }
    }

    /// A capsule behind a toolbar item that isn't a button. iOS 26 puts toolbar items on Liquid
    /// Glass already, so it's only drawn before that.
    func toolbarPill() -> some View {
        modifier(ToolbarPillModifier())
    }
}

private struct ToolbarPillModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(.horizontal, LKSpacing.xs)
        } else {
            content
                .padding(.horizontal, LKSpacing.m)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
    }
}

/// Coins, with the coin symbol: "120".
struct CoinCount: View {
    let coins: Int

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            Image(systemName: LockinSymbol.coin)
                .foregroundStyle(LockinColour.coin)
            Text(coins, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(coins)))
        }
        .font(LKFont.subheadline.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(coins == 1 ? "1 coin" : "\(coins) coins"))
    }
}

/// A small orange crown on a disc: the corner badge on anything that needs Plus.
struct PlusBadge: View {
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: LockinSymbol.plus)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LockinColour.plus.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Tiles that act as buttons (durations, creature parts) shrink a little while pressed, like the
/// system's own.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(LKMotion.press, value: configuration.isPressed)
    }
}
