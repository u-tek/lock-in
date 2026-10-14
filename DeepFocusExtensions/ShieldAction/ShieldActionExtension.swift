import DeepFocus
import Foundation
import ManagedSettings

/// Handles the buttons on Deep Focus's shield.
///
/// - "Back to focus" closes the app (`.close`).
/// - "Open anyway" records a slip in the App Group (the app sends it later: this extension is
///   assumed to have no network, SPEC.md §9.3), takes the app out of the `.lockin` store's shields
///   for five minutes, and answers `.defer`, which redraws the shield; with the app no longer
///   shielded, it goes and the app opens. A DeviceActivity schedule (`.lockinGrace`) ends with the
///   grace, and the monitor extension shields the app again.
///
/// A separate store can't do the grace: stores combine with the most restrictive setting winning,
/// so only the store that shields an app can let it through. The system gives this extension a
/// token, never a name; for an app chosen through its category it gives the category's token, so
/// "Open anyway" there lets the whole category through for the five minutes.
final class ShieldActionExtension: ShieldActionDelegate {
    private let engine = DeepFocusEngine.live()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action, target: .application, token: application))
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action, target: .webDomain, token: webDomain))
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action, target: .category, token: category))
    }

    private func respond<T: Encodable>(to action: ShieldAction, target: DeepFocusShieldTarget, token: T) -> ShieldActionResponse {
        let button: DeepFocusShieldButton
        switch action {
        case .primaryButtonPressed:
            button = .primary
        case .secondaryButtonPressed:
            button = .secondary
        default:
            // The secondary button's submenu items (iOS 26.4). Lockin's shield has no submenu.
            return ShieldActionResponse.none
        }
        let encoded = try? JSONEncoder().encode(token)
        switch engine.handleShieldAction(button, target: target, token: encoded) {
        case .closeApp:
            return ShieldActionResponse.close
        case .redrawShield:
            return ShieldActionResponse.`defer`
        case .keepShield:
            return ShieldActionResponse.none
        }
    }
}
