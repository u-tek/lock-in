// Notifications (M4, docs/milestones/M4.md): what the app needs to know about its alerts.
//
// - `LockinNotificationCategory`: the "is locking in" alert's category, `LK_LOCKIN`, and its two
//   buttons, Join 25 and Join 50.
// - `LockInAlert`: the alert's own payload, the `lk` dictionary beside `aps`.
// - `NotificationRoute`: what a tap on the alert, or on one of its buttons, asks the app to do.
// - `QuietHours`: when squad alerts stay away (22:00–07:00 by default), kept in the App Group.
// - `JoinWithoutOpening`: the push-to-start spike's developer switch and the token it needs.
//
// Plain values only: no session engine and no network, so every rule here is unit-tested. The
// app target is the notification centre's delegate and does the joining.

import Foundation
import Model
import UserNotifications

/// The "is locking in" alert's category (SPEC.md §4.5): `LK_LOCKIN`, with Join 25 and Join 50.
///
/// The server sets `aps.category` to `identifier`; the app registers the category at launch, so iOS
/// shows the two buttons when the alert is long-pressed or pulled down.
///
/// By default the buttons open the app (`.foreground`): it joins the room and starts the Live
/// Activity itself (§4.5 step 2). The push-to-start spike's developer switch registers them
/// without `.foreground` instead: they run in the background, and the server starts the activity
/// by push (step 3, docs/spikes/push-to-start.md).
public enum LockinNotificationCategory {
    /// `aps.category` of the "is locking in" alert. The server sends the same string
    /// (`LOCKIN_CATEGORY` in server/src/alerts.ts).
    public static let identifier = "LK_LOCKIN"
    /// Join 25: join the room for 25 minutes.
    public static let join25 = "LK_JOIN_25"
    /// Join 50: join the room for 50 minutes.
    public static let join50 = "LK_JOIN_50"

    /// The category to register. Join 25 and Join 50 open the app, or, with `joinsInBackground`
    /// (the push-to-start spike), run without opening it, from the Lock Screen too.
    public static func category(joinsInBackground: Bool = false) -> UNNotificationCategory {
        let options: UNNotificationActionOptions = joinsInBackground ? [] : [.foreground]
        let actions = [join25, join50].map { action in
            UNNotificationAction(
                identifier: action,
                title: title(forAction: action),
                options: options,
                icon: UNNotificationActionIcon(systemImageName: "lock.fill")
            )
        }
        return UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [], options: [])
    }

    /// Every category the app registers (`UNUserNotificationCenter.setNotificationCategories`).
    /// Registering again replaces the lot, which is how the developer switch takes effect.
    public static func all(joinsInBackground: Bool = false) -> Set<UNNotificationCategory> {
        [category(joinsInBackground: joinsInBackground)]
    }

    /// The minutes a join button stands for; nil for anything else (a tap on the alert itself, a
    /// dismissal, a button a later version adds).
    public static func minutes(forAction identifier: String) -> Int? {
        switch identifier {
        case join25: SessionPreset.twentyFive.minutes
        case join50: SessionPreset.fifty.minutes
        default: nil
        }
    }

    /// "Join 25", "Join 50".
    static func title(forAction identifier: String) -> String {
        guard let minutes = minutes(forAction: identifier) else { return "Join" }
        return "Join \(minutes)"
    }
}
