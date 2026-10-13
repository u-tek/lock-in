import Core
import Foundation
import SwiftUI

/// Screens pushed onto Home's navigation stack.
enum AppRoute: Hashable {
    case developer
    case apnsSpike
    case liveActivityLab
    case designTokens

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .developer: DeveloperMenu()
        case .apnsSpike: APNsSpikeScreen()
        case .liveActivityLab: LiveActivityLabScreen()
        case .designTokens: DesignTokensScreen()
        }
    }
}

/// `lockin://` links the app opens: from the Live Activity now, and from widgets and invite links
/// later (SPEC.md §1.7).
enum DeepLink: Equatable {
    /// `lockin://session/<sid>`: the Live Activity's `widgetURL`. The widget extension builds the
    /// same URL in `Widgets/LockinLiveActivity.swift`; change both together.
    case session(id: String)

    static let scheme = "lockin"

    init?(url: URL) {
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
