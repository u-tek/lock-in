import ActivityKit
import API
import Combine
import Core
import Foundation
import LiveActivity
import Model
import Notifications
import Paywall
import SessionEngine
import Social
import UIKit
import UserNotifications

/// What the app's screens share, made once per launch.
@MainActor
enum AppServices {
    /// Event counts only (SPEC.md §5.6). No provider is chosen yet, so they go to the unified log.
    /// docs/decisions/0010-analytics-provider.md proposes none: a sink that batches the counts
    /// once a day to the Worker's `POST /metrics` (built, server/src/metrics.ts). Left on the log
    /// until the owner decides.
    static let analytics: Analytics = .debugLog

    static let liveActivities = LiveActivityController(analytics: analytics)

    /// The running app's services, for the app delegate. Nil in snapshot mode.
    static weak var live: LiveServices?

    /// This phone's APNs device token as hex, once iOS hands it over (`LockinAppDelegate`).
    static var deviceToken: String?

    /// What a tap on an "is locking in" alert asks the screens to do (M4).
    static let notificationInbox = NotificationInbox()

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
    /// An activity the session engine took up again from its saved session, solo or squad, is
    /// left alone (`keeping`); everything else (a crash's leftovers, the APNs spike's) ends.
    ///
    /// Only the noted ids, never everything running: the root view's task runs again when the
    /// system reconnects the scene within the same launch, and an activity started since must
    /// survive that. Ended activities drop out of `activities`, so a second run ends nothing.
    static func endOrphanedActivities(keeping isOwned: (String) -> Bool) async {
        let orphans = liveActivities.activities.filter { activity in
            orphanIDs.contains(activity.id) && !isOwned(activity.id)
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
    /// What the Home and Lock Screen widgets show, kept in the App Group (M6).
    let widgets = WidgetDataWriter()
    /// Deep Focus's shields following the session, and its slips (M8).
    let deepFocus: DeepFocusCoordinator

    /// The latest push-to-start token, for the M4 spike (`devices.push_to_start_token`). Saved
    /// in the App Group as it arrives, so a background launch has it straight away.
    private var pushToStartToken: String?
    /// Lockin Plus following the account (M7).
    private var plusFollowsAccount: AnyCancellable?

    init() {
        let engine = SessionEngine(liveActivities: AppServices.liveActivities)
        self.engine = engine
        // Through RevenueCat when the build has its key (LK_REVENUECAT_KEY, M7), else StoreKit 2.
        plus = PlusStore(
            bundleID: Bundle.main.bundleIdentifier ?? "com.example.lockin",
            revenueCatKey: AppConfiguration.main.revenueCatAPIKey
        )
        // Paywall views, trials and purchases: counts only (SPEC.md §5.6).
        plus.analytics = AppServices.analytics
        // The API host and the Keychain token come from the build and the phone.
        let api = APIClient()
        let account = AccountStore(api: api)
        let friends = FriendsStore(api: api, account: account)
        friends.analytics = AppServices.analytics
        // Coins and Lockling items (M5): the server's signed in, this phone's signed out, which
        // follow the engine's count.
        let shop = ShopStore(api: api, account: account, wallet: .appGroup(), wearing: engine.avatar, localEarned: engine.stats.coins)
        engine.$stats.map(\.coins).removeDuplicates().assign(to: &shop.$localEarned)
        social = SocialModels(
            account: account,
            friends: friends,
            // With the account, so signing out (or a 401) empties the list.
            squads: SquadsStore(api: api, account: account),
            rooms: SquadRooms(api: api),
            shop: shop
        )
        // Squad sessions go through the server; without one the engine runs solo only.
        if api.isConfigured {
            engine.configure(api: api)
        }
        pushToStartToken = JoinWithoutOpening.savedToken()
        // The Live Activity's Pause, Resume and End buttons, and the Lock in widget's and
        // control's Start, run their intents in this process; the bridge hands them to the engine.
        SessionIntentBridge.shared.handler = { command in
            await engine.handle(command)
        }
        // A session may have ended while the app was away.
        engine.reconcile()
        deepFocus = DeepFocusCoordinator(engine: engine, plus: plus)
        // From here on, including a background launch for the Lock in widget's button.
        widgets.watch(engine: engine, social: social)
        // Lockin Plus follows the account (M7): its `plusUntil` counts, RevenueCat knows purchases
        // by its id, and after a purchase or a restore the server checks with RevenueCat.
        let plus = self.plus
        plus.afterPurchase = { [weak account] in
            _ = await account?.refreshPlus()
        }
        plusFollowsAccount = account.$state.sink { state in
            MainActor.assumeIsolated {
                plus.noteAccount(id: state.user?.id, plusUntil: state.user?.plusUntil)
            }
        }
        AppServices.analytics.track(.appOpened)
    }

    /// Clears up after earlier launches. Run once the first screen is up.
    func endOrphanedActivities() async {
        let engine = engine
        await AppServices.endOrphanedActivities(keeping: { engine.ownsActivity(id: $0) })
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
            tz: TimeZone.current.identifier,
            quietHours: QuietHours.load().deviceSetting
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
            JoinWithoutOpening.save(token: token)
            registerDevice()
        }
    }

    // MARK: - "Is locking in" alerts (M4)

    /// Does what a tap on an alert, or on its Join 25 or Join 50, asks. Returns once a join has
    /// finished, or in the background after `backgroundJoinLimit` at most, so the notification
    /// centre can be told it's done.
    func respond(to route: NotificationRoute) async {
        let inbox = AppServices.notificationInbox
        switch route {
        case .none:
            return
        case .openSquad(let squadId):
            AppServices.analytics.track(.notificationOpened)
            inbox.pick(squadId)
            // So Home knows the room is open, and says "Join in".
            await social.refreshSquads()
        case .join(let sessionId, let squadId, let minutes):
            AppServices.analytics.track(.notificationJoin, counts: ["minutes": minutes])
            if JoinWithoutOpening.isEnabled(), UIApplication.shared.applicationState != .active {
                await joinWithoutOpening(sessionId: sessionId, squadId: squadId, minutes: minutes)
            } else {
                inbox.pick(squadId)
                await join(sessionId: sessionId, squadId: squadId, minutes: minutes)
            }
        }
    }

    /// Join 25 or Join 50 that opened the app: joins the room, and the session screen comes up
    /// with the session (`RootView`).
    private func join(sessionId: String, squadId: String, minutes: Int) async {
        do {
            try await engine.joinSquadSession(sessionId: sessionId, squadId: squadId, minutes: minutes)
        } catch is CancellationError {
            return
        } catch SquadSessionError.sessionInProgress {
            // A session is already on screen: it stays.
            return
        } catch {
            AppServices.notificationInbox.failure = error.squadMessage
            return
        }
        // Joined before the app was quite in the foreground, so the Live Activity couldn't start
        // yet. It can as soon as the app is active.
        guard engine.liveActivityProblem == .notInForeground else { return }
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(250))
        }
        engine.reconcile()
    }

    /// How long a background join may keep the notification centre waiting: iOS gives a
    /// background button about 30 seconds.
    static let backgroundJoinLimit: Duration = .seconds(20)

    /// The push-to-start spike (docs/spikes/push-to-start.md): Join 25 or Join 50 without opening
    /// the app. The join carries the push-to-start token, the server starts the Live Activity by
    /// push, and the session engine takes up the activity iOS starts. If the server couldn't, the
    /// activity starts the next time the app is in the foreground.
    private func joinWithoutOpening(sessionId: String, squadId: String, minutes: Int) async {
        let began = Date()
        // Push-to-start can't show anything while Live Activities are switched off.
        let token = AppServices.liveActivities.areActivitiesEnabled ? (pushToStartToken ?? JoinWithoutOpening.savedToken()) : nil
        let pushToStart = token.map { PushToStart(token: $0, env: APNsEnvironment.current) }
        if pushToStart == nil {
            Log.push.info("No push-to-start token for a background join")
        }
        let engine = self.engine
        let work = Task { @MainActor in
            var outcome = JoinWithoutOpening.Attempt.Outcome.failed
            do {
                let pushed = try await engine.joinSquadSession(
                    sessionId: sessionId,
                    squadId: squadId,
                    minutes: minutes,
                    pushToStart: pushToStart
                )
                outcome = pushed ? .pushedToStart : .notPushed
                if pushed {
                    AppServices.analytics.track(.pushToStartJoin)
                }
            } catch {
                Log.push.error("Couldn't join from the background")
            }
            LiveServices.record(outcome, since: began)
        }
        let finished = await AppServices.wait(for: work, atMost: Self.backgroundJoinLimit)
        if !finished {
            Log.push.error("A background join was still waiting when its time ran out")
            Self.record(.timedOut, since: began)
        }
    }

    /// Notes how a background join went, for the Developer menu.
    private static func record(_ outcome: JoinWithoutOpening.Attempt.Outcome, since began: Date) {
        let now = Date()
        JoinWithoutOpening.record(JoinWithoutOpening.Attempt(
            outcome: outcome,
            at: now.timeIntervalSince1970,
            seconds: now.timeIntervalSince(began)
        ))
    }
}

private extension QuietHours {
    /// As `POST /devices` takes it.
    var deviceSetting: DeviceQuietHours {
        guard let window else { return .off }
        return .window(start: window.start, end: window.end)
    }
}

/// The account, friends and squads, handed down together.
struct SocialModels {
    let account: AccountStore
    let friends: FriendsStore
    let squads: SquadsStore
    /// How many are locked in in each squad's open room, for Home's picker.
    let rooms: SquadRooms
    /// Coins, the Lockling items you own, and the coin shop (M5).
    let shop: ShopStore

    /// Fetches the squads, then peeks into the ones with an open room. Signed out (or without a
    /// handle yet) there are no squads to fetch.
    @MainActor
    func refreshSquads() async {
        guard account.state.isSignedIn else { return }
        await squads.refresh()
        await rooms.refresh(squads.squads)
    }
}

/// Only what SwiftUI has no hook for: the APNs device token, and the notification centre's
/// delegate (alerts in the foreground, and taps on them).
final class LockinAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if SnapshotMode.current == nil {
            // Before returning: a tap on an alert that launched the app is handed over next.
            UNUserNotificationCenter.current().delegate = self
            SquadAlerts.registerCategories()
        }
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

extension LockinAppDelegate: UNUserNotificationCenterDelegate {
    /// An alert while the app is open shows as a banner, unless this phone is already in the
    /// session it's about.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let sessionId = LockInAlert(userInfo: notification.request.content.userInfo)?.sessionId
        let isInIt = await LockinAppDelegate.isInSession(sessionId)
        return isInIt ? [] : [.banner, .list, .sound]
    }

    /// A tap on an alert or one of its buttons. iOS waits for this to return before it suspends
    /// the app again, which for a background Join is at most `LiveServices.backgroundJoinLimit`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = NotificationRoute.route(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        await LockinAppDelegate.respond(to: route)
    }

    @MainActor
    private static func isInSession(_ sessionId: String?) -> Bool {
        guard let sessionId, let engine = AppServices.live?.engine else { return false }
        return engine.mode.sessionId == sessionId
    }

    @MainActor
    private static func respond(to route: NotificationRoute) async {
        await AppServices.live?.respond(to: route)
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
