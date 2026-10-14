import Foundation
import UserNotifications

/// What a tap on one of Lockin's alerts asks the app to do.
public enum NotificationRoute: Hashable, Sendable {
    /// Join 25 or Join 50: join the alert's room for `minutes`, and show the session.
    case join(sessionId: String, squadId: String, minutes: Int)
    /// The alert itself: open Home with the squad picked, where "Join in" is waiting.
    case openSquad(squadId: String)
    /// Nothing for the app to do: the alert was dismissed, or it isn't one of Lockin's.
    case none

    /// Reads a notification response: the button tapped (`UNNotificationResponse.actionIdentifier`)
    /// and the alert's payload (`request.content.userInfo`).
    public static func route(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> NotificationRoute {
        guard let alert = LockInAlert(userInfo: userInfo) else { return .none }
        if let minutes = LockinNotificationCategory.minutes(forAction: actionIdentifier) {
            return .join(sessionId: alert.sessionId, squadId: alert.squadId, minutes: minutes)
        }
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            return .openSquad(squadId: alert.squadId)
        }
        return .none
    }

    /// The squad the alert was about, if there is one.
    public var squadId: String? {
        switch self {
        case .join(_, let squadId, _): squadId
        case .openSquad(let squadId): squadId
        case .none: nil
        }
    }
}
