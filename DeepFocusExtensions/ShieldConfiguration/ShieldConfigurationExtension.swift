import DeepFocus
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws Deep Focus's shield over an app or website the person blocked: their Lockling,
/// "You're locked in", "Back to focus" and "Open anyway". LockinShieldAction handles the buttons.
///
/// The system runs this in a sandbox with no network that keeps what it's told (app names) inside
/// the extension, and draws its own default shield if the answer is slow
/// (ShieldConfigurationDataSource). So it only reads: the session state and the Lockling's avatar
/// code, both from the App Group. The app's name goes on the shield and nowhere else.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let engine = DeepFocusEngine.live()

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(naming: application.localizedDisplayName)
    }

    /// An app shielded because the person chose its whole category.
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shield(naming: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(naming: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shield(naming: webDomain.domain)
    }

    private func shield(naming name: String?) -> ShieldConfiguration {
        let content = engine.shieldContent(appName: name)
        return ShieldConfiguration(
            backgroundBlurStyle: ShieldStyle.backgroundBlurStyle,
            backgroundColor: ShieldStyle.backgroundColor,
            icon: ShieldIcon.image(),
            title: ShieldConfiguration.Label(text: content.title, color: ShieldStyle.titleColor),
            subtitle: ShieldConfiguration.Label(text: content.subtitle, color: ShieldStyle.subtitleColor),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: content.primaryButton,
                color: ShieldStyle.primaryButtonLabelColor
            ),
            primaryButtonBackgroundColor: ShieldStyle.primaryButtonBackgroundColor,
            secondaryButtonLabel: content.secondaryButton.map {
                ShieldConfiguration.Label(text: $0, color: ShieldStyle.secondaryButtonLabelColor)
            }
        )
    }
}
