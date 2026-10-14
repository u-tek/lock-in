import DesignSystem
import Foundation
import UIKit

/// The words on Deep Focus's shield. The shield configuration extension puts them in a
/// `ShieldConfiguration` with `ShieldStyle`'s colours and `ShieldIcon`'s Lockling.
public struct ShieldContent: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var primaryButton: String
    /// Nil hides the second button.
    public var secondaryButton: String?

    public init(title: String, subtitle: String, primaryButton: String, secondaryButton: String?) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }

    /// During a session: back to focus, or open anyway, which is a slip.
    ///
    /// - Parameters:
    ///   - appName: The shielded app's or website's name as the system gave it; "This app" when
    ///     it gave none.
    ///   - withSquad: Friends are in the session. Alone, there's no squad to mention.
    public static func locked(appName: String?, withSquad: Bool) -> ShieldContent {
        let name = displayName(appName)
        return ShieldContent(
            title: "You're locked in",
            subtitle: withSquad
                ? "\(name) can wait. Your squad's still going."
                : "\(name) can wait. Your session's still going.",
            primaryButton: "Back to focus",
            secondaryButton: "Open anyway"
        )
    }

    /// A shield still up when no session is: Lockin wasn't running to lift it, and the monitor
    /// extension wasn't called in time. Its one button takes every shield down.
    public static func lifted(appName: String?) -> ShieldContent {
        ShieldContent(
            title: "You're not locked in",
            subtitle: "\(displayName(appName)) isn't blocked right now.",
            primaryButton: "Unlock",
            secondaryButton: nil
        )
    }

    /// Longer names are cut with an ellipsis, so the subtitle stays a line or two.
    static let maximumNameLength = 30

    /// The name as given, trimmed and cut to length, or "This app".
    static func displayName(_ appName: String?) -> String {
        let trimmed = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "This app" }
        guard trimmed.count > maximumNameLength else { return trimmed }
        let cut = trimmed.prefix(maximumNameLength - 1).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }
}

/// The shield's look: the system's thick material with Lockin's indigo, so it reads like part of
/// iOS rather than a poster. Colours are the system's dynamic ones and follow light and dark.
public enum ShieldStyle {
    public static var backgroundBlurStyle: UIBlurEffect.Style {
        .systemThickMaterial
    }

    /// A faint wash of the tint under the material.
    public static var backgroundColor: UIColor {
        tint.withAlphaComponent(0.08)
    }

    /// Lockin's one brand colour, system indigo (DesignSystem's `tint`).
    public static var tint: UIColor {
        LKColorCatalogue.tint.uiColor
    }

    public static var titleColor: UIColor {
        LKColorCatalogue.textPrimary.uiColor
    }

    public static var subtitleColor: UIColor {
        LKColorCatalogue.textSecondary.uiColor
    }

    public static var primaryButtonLabelColor: UIColor {
        .white
    }

    public static var primaryButtonBackgroundColor: UIColor {
        tint
    }

    public static var secondaryButtonLabelColor: UIColor {
        tint
    }
}
