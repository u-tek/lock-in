import ActivityKit
import Core
import Foundation
import LiveActivity
import Paywall
import SessionEngine

/// What the app's screens share, made once per launch.
@MainActor
enum AppServices {
    /// Event counts only (SPEC.md §5.6). No vendor is chosen yet, so they go to the unified log.
    static let analytics: Analytics = .debugLog

    static let liveActivities = LiveActivityController(analytics: analytics)

    /// Activities that were already running when this launch began, by id.
    private(set) static var orphanIDs: Set<String> = []

    /// Notes which activities may be orphans. Call before any screen exists, so a screen opened by
    /// tapping an activity at launch can't take up one that's about to be ended.
    static func noteOrphanedActivities() {
        orphanIDs = Set(liveActivities.activities.map(\.id))
    }

    /// Ends the Live Activities noted by `noteOrphanedActivities()` that nothing will pick up
    /// again: left by a crash or a killed app, they'd otherwise sit in the island until the
    /// system's 8-hour cap (CLAUDE.md, "Live Activity rules").
    ///
    /// A solo activity can be the session engine's own, which it takes up again when it
    /// reconciles its saved session, so solo ones are left alone while there's a session for
    /// them to belong to (`hasSession`). Squad activities only come from the APNs spike, which
    /// keeps nothing between launches.
    ///
    /// Only the noted ids, never everything running: the root view's task runs again when the
    /// system reconnects the scene within the same launch, and an activity started since must
    /// survive that. Ended activities drop out of `activities`, so a second run ends nothing.
    static func endOrphanedActivities(hasSession: Bool) async {
        let orphans = liveActivities.activities.filter { activity in
            guard orphanIDs.contains(activity.id) else { return false }
            return !(hasSession && activity.attributes.isSolo)
        }
        for activity in orphans {
            await liveActivities.end(activity, state: nil, dismissal: .immediate)
        }
        if !orphans.isEmpty {
            Log.liveActivity.info("Ended \(orphans.count, privacy: .public) orphaned activities")
        }
    }
}

/// The models behind the real app (not snapshots): the session engine and Lockin Plus.
@MainActor
final class LiveServices {
    let engine: SessionEngine
    let plus: PlusStore

    init() {
        let engine = SessionEngine(liveActivities: AppServices.liveActivities)
        self.engine = engine
        plus = PlusStore(bundleID: Bundle.main.bundleIdentifier ?? "com.example.lockin")
        // Paywall views, trials and purchases: counts only (SPEC.md §5.6).
        plus.analytics = AppServices.analytics
        // The Live Activity's Pause, Resume and End buttons run their intents in this process;
        // the bridge hands them to the engine.
        SessionIntentBridge.shared.handler = { command in
            await engine.handle(command)
        }
        // A session may have ended while the app was away.
        engine.reconcile()
        AppServices.analytics.track(.appOpened)
    }

    /// Clears up after earlier launches. Run once the first screen is up.
    func endOrphanedActivities() async {
        await AppServices.endOrphanedActivities(hasSession: engine.phase != .idle)
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
