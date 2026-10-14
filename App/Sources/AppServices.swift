import ActivityKit
import API
import Core
import Foundation
import LiveActivity
import Model
import Paywall
import SessionEngine
import Social
import UIKit

/// What the app's screens share, made once per launch.
@MainActor
enum AppServices {
    /// Event counts only (SPEC.md §5.6). No vendor is chosen yet, so they go to the unified log.
    static let analytics: Analytics = .debugLog

    static let liveActivities = LiveActivityController(analytics: analytics)

    /// The running app's services, for the app delegate. Nil in snapshot mode.
    static weak var live: LiveServices?

    /// This phone's APNs device token as hex, once iOS hands it over (`LockinAppDelegate`).
    static var deviceToken: String?

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

/// The models behind the real app (not snapshots): the session engine, Lockin Plus, and the
/// account and friends.
@MainActor
final class LiveServices {
    let engine: SessionEngine
    let plus: PlusStore
    let social: SocialModels

    /// The latest push-to-start token, for the M4 spike (`devices.push_to_start_token`).
    private var pushToStartToken: String?

    init() {
        let engine = SessionEngine(liveActivities: AppServices.liveActivities)
        self.engine = engine
        plus = PlusStore(bundleID: Bundle.main.bundleIdentifier ?? "com.example.lockin")
        // Paywall views, trials and purchases: counts only (SPEC.md §5.6).
        plus.analytics = AppServices.analytics
        // The API host and the Keychain token come from the build and the phone.
        let api = APIClient()
        let account = AccountStore(api: api)
        let friends = FriendsStore(api: api, account: account)
        friends.analytics = AppServices.analytics
        social = SocialModels(account: account, friends: friends)
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

    // MARK: - This phone, for pushes

    /// Registers this phone with the server (`POST /devices`) with everything known so far. The
    /// account store holds it until someone signs in, and skips a registration it already sent.
    func registerDevice() {
        guard social.account.isConfigured, let token = AppServices.deviceToken else { return }
        let liveActivities = AppServices.liveActivities
        let device = DeviceRegistration(
            apnsToken: token,
            env: APNsEnvironment.current,
            pushToStartToken: pushToStartToken,
            laEnabled: liveActivities.areActivitiesEnabled,
            frequentPushes: liveActivities.frequentPushesEnabled,
            tz: TimeZone.current.identifier
        )
        let account = social.account
        Task {
            await account.registerDevice(device)
        }
    }

    /// Live Activities switched on or off in Settings: the server stops or starts pushing them.
    /// Runs for as long as the calling task.
    func watchLiveActivitySettings() async {
        for await _ in AppServices.liveActivities.enablementUpdates {
            registerDevice()
        }
    }

    /// The push-to-start token, whenever iOS issues a new one. Runs for as long as the calling
    /// task.
    func watchPushToStartTokens() async {
        for await token in AppServices.liveActivities.pushToStartTokens() {
            pushToStartToken = token
            registerDevice()
        }
    }
}

/// The account and friends stores, handed down together.
struct SocialModels {
    let account: AccountStore
    let friends: FriendsStore
}

/// Only what SwiftUI has no hook for: the APNs device token.
final class LockinAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // No prompt: the token comes whether or not alerts are allowed. Without a server
        // there's nowhere to send it, and snapshots never touch the system.
        if SnapshotMode.current == nil, AppConfiguration.main.apiBaseURL != nil {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppServices.deviceToken = PushToken.hex(deviceToken)
        AppServices.live?.registerDevice()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Expected on the simulator and in unsigned builds.
        Log.push.error("Couldn't register for remote notifications")
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
