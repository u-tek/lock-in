// LiveActivity: the Live Activity's plumbing and its looks.
//
// - `LiveActivityController` starts, updates and ends activities from the app, and turns their
//   push tokens into hex strings to upload.
// - `LiveActivityPresentation` decides what each presentation shows; the views in `Views/` lay it
//   out. The widget extension and the app's Live Activity Lab draw the same views from the same
//   `(attributes, state)`, so what CI snapshots is what the Lock Screen shows.
// - `LiveActivitySamples` are fake squads for the Lab and previews.
//
// - `SessionIntents.swift` has the activity's buttons (`LiveActivityIntent`s) and the bridge that
//   hands their commands to the app.
//
// The widget extension links this module too, so nothing here may use extension-unavailable API
// (`UIApplication` and friends) or the network.

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Core
import Foundation
import Model

/// The app's Live Activity, as ActivityKit knows it.
public typealias LockinActivity = Activity<LockinAttributes>

/// Starts, updates and ends the app's Live Activities, and hands out their push tokens.
///
/// App-side only: the widget extension draws activities but never starts them. Every update goes
/// in with a stale date 5 minutes after the last running timer (`ContentState.staleDate(now:)`),
/// so a missed push shows as out of date rather than wrong.
@MainActor
public final class LiveActivityController {
    private let analytics: Analytics

    public init(analytics: Analytics = .disabled) {
        self.analytics = analytics
    }

    // MARK: - Permission

    /// Off when the user has switched Live Activities off for the app in Settings.
    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Whether the user allows more frequent updates (`NSSupportsLiveActivitiesFrequentUpdates`).
    /// Reported to the server with the device (`devices.frequent_pushes`).
    public var frequentPushesEnabled: Bool {
        ActivityAuthorizationInfo().frequentPushesEnabled
    }

    /// Whether Live Activities are enabled: the current value first, then every change made in
    /// Settings. A new stream each time it's read; it ends when the reading task is cancelled.
    public var enablementUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                // Held for the whole loop: the updates belong to this instance.
                let info = ActivityAuthorizationInfo()
                continuation.yield(info.areActivitiesEnabled)
                for await enabled in info.activityEnablementUpdates {
                    continuation.yield(enabled)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Activities

    /// The app's activities that haven't ended.
    public var activities: [LockinActivity] {
        LockinActivity.activities.filter { Self.isRunning($0) }
    }

    /// Starts an activity that receives updates by push token. Call it while the app is in the
    /// foreground, then upload each token from `pushTokens(of:)`.
    ///
    /// - Parameter takesPushes: False starts one the app updates itself, for a build without the
    ///   push entitlement; ActivityKit refuses a push-token activity there.
    @discardableResult
    public func start(
        attributes: LockinAttributes,
        state: LockinAttributes.ContentState,
        now: Date = Date(),
        takesPushes: Bool = true
    ) throws -> LockinActivity {
        do {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw LiveActivityError.disabled }
            // ActivityKit would refuse too, but only at the system's 4 KB. The server holds every
            // payload to 3.5 KB, and a start the server couldn't follow with pushes is no use.
            guard attributes.fitsPayloadBudget(state) else { throw LiveActivityError.tooLarge }
            let activity = try LockinActivity.request(
                attributes: attributes,
                content: content(attributes: attributes, state: state, now: now),
                // Without pushes only for a build that can't take them: the simulator builds CI
                // films, which are unsigned and so have no push entitlement (IslandDemo).
                pushType: takesPushes ? .token : nil
            )
            Log.liveActivity.info("Started activity for session \(attributes.sid, privacy: .public)")
            analytics.track(.liveActivityStarted)
            return activity
        } catch {
            let reason = LiveActivityError(error)
            Log.liveActivity.error("Couldn't start activity for session \(attributes.sid, privacy: .public): \(reason.description, privacy: .public)")
            analytics.track(reason == .disabled ? .liveActivitiesDisabled : .liveActivityFailed)
            throw reason
        }
    }

    /// Shows `state`, unless the activity already shows a newer version or `state` is over the
    /// payload budget. Returns whether it went through.
    @discardableResult
    public func update(
        _ activity: LockinActivity,
        state: LockinAttributes.ContentState,
        now: Date = Date()
    ) async -> Bool {
        let current = activity.content.state
        guard ContentPolicy.accepts(state, over: current) else {
            Log.liveActivity.debug("Skipped update to v\(state.v, privacy: .public): v\(current.v, privacy: .public) is showing")
            return false
        }
        guard activity.attributes.fitsPayloadBudget(state) else {
            Log.liveActivity.error("Skipped update to v\(state.v, privacy: .public): over the payload budget")
            return false
        }
        await activity.update(content(attributes: activity.attributes, state: state, now: now))
        return true
    }

    /// Ends the activity, showing `state` as its final content when it's at least as new as what's
    /// on screen (otherwise the newer content stays).
    ///
    /// - Parameter dismissal: When it leaves the Lock Screen. Nil means 30 minutes from `now`
    ///   (SPEC.md §4.4), matching the server's `end` push.
    public func end(
        _ activity: LockinActivity,
        state: LockinAttributes.ContentState?,
        dismissal: ActivityUIDismissalPolicy? = nil,
        now: Date = Date()
    ) async {
        var finalContent: ActivityContent<LockinAttributes.ContentState>?
        if let state,
           ContentPolicy.accepts(state, over: activity.content.state),
           activity.attributes.fitsPayloadBudget(state) {
            // An ended activity can't go stale, so no stale date.
            finalContent = ActivityContent(
                state: state,
                staleDate: nil,
                relevanceScore: ContentPolicy.relevanceScore(for: activity.attributes)
            )
        }
        let policy = dismissal ?? .after(ContentPolicy.dismissalDate(endingAt: now))
        await activity.end(finalContent, dismissalPolicy: policy)
        Log.liveActivity.info("Ended activity for session \(activity.attributes.sid, privacy: .public)")
    }

    /// Ends every running activity except `activityID`, straight away. Call on launch: an
    /// activity left by a crash or a killed app would otherwise sit in the island until the
    /// system's 8-hour cap. Returns how many were ended.
    @discardableResult
    public func endOrphans(keeping activityID: String?) async -> Int {
        var ended = 0
        for activity in LockinActivity.activities where activity.id != activityID && Self.isRunning(activity) {
            await activity.end(nil, dismissalPolicy: .immediate)
            ended += 1
        }
        if ended > 0 {
            Log.liveActivity.info("Ended \(ended, privacy: .public) orphaned activities")
        }
        return ended
    }

    // MARK: - Push tokens

    /// The activity's push token as lowercase hex: the current one if it has arrived, then each
    /// new one. Tokens arrive asynchronously and can change while the activity runs; upload every
    /// one (CLAUDE.md, "Live Activity rules"). Repeats in a row are dropped.
    public func pushTokens(of activity: LockinActivity) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                var last: String?
                if let data = activity.pushToken {
                    let token = PushToken.hex(data)
                    last = token
                    continuation.yield(token)
                }
                for await data in activity.pushTokenUpdates {
                    let token = PushToken.hex(data)
                    guard token != last else { continue }
                    last = token
                    continuation.yield(token)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The app's push-to-start token as lowercase hex, current one first, then each new one. For
    /// the M4 push-to-start spike; the server stores it per device (`devices.push_to_start_token`).
    public func pushToStartTokens() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                var last: String?
                if let data = LockinActivity.pushToStartToken {
                    let token = PushToken.hex(data)
                    last = token
                    continuation.yield(token)
                }
                for await data in LockinActivity.pushToStartTokenUpdates {
                    let token = PushToken.hex(data)
                    guard token != last else { continue }
                    last = token
                    continuation.yield(token)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func content(
        attributes: LockinAttributes,
        state: LockinAttributes.ContentState,
        now: Date
    ) -> ActivityContent<LockinAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: state.staleDate(now: now),
            relevanceScore: ContentPolicy.relevanceScore(for: attributes)
        )
    }

    /// Not yet ended or dismissed: active, stale, or a state a later iOS adds.
    private static func isRunning(_ activity: LockinActivity) -> Bool {
        activity.activityState != .ended && activity.activityState != .dismissed
    }
}
#endif
