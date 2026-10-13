import Core
import Foundation
import LiveActivity

/// What the app's screens share. M0 has no app model yet: no sessions, no account, no backend.
/// M1 replaces this with one when solo sessions arrive.
@MainActor
enum AppServices {
    /// Event counts only (SPEC.md §5.6). No vendor is chosen yet, so they go to the unified log.
    static let analytics: Analytics = .debugLog

    static let liveActivities = LiveActivityController(analytics: analytics)

    /// Activities that were already running when this launch began, by id.
    private(set) static var orphanIDs: Set<String> = []

    /// Notes which activities are orphans. Call before any screen exists, so a screen opened by
    /// tapping an activity at launch can't take up one that's about to be ended.
    static func noteOrphanedActivities() {
        orphanIDs = Set(liveActivities.activities.map(\.id))
    }

    /// Ends every Live Activity left running from an earlier launch. M0 keeps no session between
    /// launches, so every one still running is an orphan: left by a crash or a killed app, it
    /// would otherwise sit in the island until the system's 8-hour cap (CLAUDE.md, "Live Activity
    /// rules"). M1 keeps the activity of a session that's still going.
    static func endOrphanedActivities() async {
        await liveActivities.endOrphans(keeping: nil)
    }
}

/// This install's member id: the `me` in `LockinAttributes`.
///
/// Made once and kept in the App Group's defaults, so the widget extension can read it later.
/// M2 replaces it with the server's id for the signed-in user.
enum LocalMember {
    static let defaultsKey = "LKLocalMemberID"

    static func id(defaults: UserDefaults = AppGroup.defaults() ?? .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), ShortID.isValid(existing) {
            return existing
        }
        let id = ShortID.make()
        defaults.set(id, forKey: defaultsKey)
        return id
    }
}
