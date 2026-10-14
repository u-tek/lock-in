import Core
import Foundation
import Social
import SwiftUI

/// The developer tools, pushed onto the Settings sheet's navigation stack once the version row
/// has been tapped five times (`SettingsScreen`).
enum AppRoute: Hashable {
    case developer
    case apnsSpike
    case liveActivityLab
    case petLab
    case designTokens

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .developer: DeveloperMenu()
        case .apnsSpike: APNsSpikeScreen()
        case .liveActivityLab: LiveActivityLabScreen()
        case .petLab: PetLabScreen()
        case .designTokens: DesignTokensScreen()
        }
    }
}

/// Links the app opens: the Live Activity's, and invite links (SPEC.md §1.7). Widgets add theirs
/// later.
enum DeepLink: Equatable {
    /// `lockin://session/<sid>`: the Live Activity's `widgetURL`. The widget extension builds the
    /// same URL in `Widgets/LockinLiveActivity.swift`; change both together.
    case session(id: String)
    /// `lockin://j/<code>`, or `https://<invite host>/j/<code>` once universal links exist (M9).
    case invite(InviteLink)

    static let scheme = "lockin"

    init?(url: URL) {
        if let invite = InviteLink(url: url) {
            self = .invite(invite)
            return
        }
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "session":
            guard let id = parts.first, ShortID.isValid(id) else { return nil }
            self = .session(id: id)
        default:
            return nil
        }
    }
}
