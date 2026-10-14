// SessionEngine: the local session. Timer state, coins and streaks, persistence, and the solo
// Live Activity that mirrors it. App only: the widget extension never runs a session.
//
// Times are stored as dates, not ticks: the timer is `endsAt`, and the Live Activity counts down
// to it on its own with `Text(timerInterval:)`. Nothing here runs once a second.

import ActivityKit
import Combine
import Core
import Foundation
import LiveActivity
import Model

/// Runs one solo session at a time and keeps the stats Home shows.
///
/// Every change is saved straight away, so a session survives the app being suspended, killed or
/// woken in the background by a Live Activity button. Call `reconcile()` at launch and whenever
/// the app comes to the foreground: a session whose time ran out meanwhile finishes then.
@MainActor
public final class SessionEngine: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(startedAt: Date, endsAt: Date, plannedMinutes: Int)
        case paused(startedAt: Date, endsAt: Date, pausedAt: Date, plannedMinutes: Int)
        case finished(SessionRecord)
    }

    @Published public private(set) var phase: Phase
    @Published public private(set) var stats: FocusStats
    /// Saved when set. Mid-session, the Live Activity picks it up too.
    @Published public var avatar: AvatarCode {
        didSet { avatarChanged(from: oldValue) }
    }
    /// Why the current session has no Live Activity, if it hasn't. The session runs regardless;
    /// the app explains, and links to Settings for `.disabled`.
    @Published public private(set) var liveActivityProblem: LiveActivityError?

    /// Counts completed sessions (SPEC.md §5.6). Event counts only.
    public var analytics: Analytics = .debugLog

    /// The solo Live Activity's name for its one member.
    static let soloName = "You"
    /// A Live Activity leaves the Dynamic Island 8 hours after it starts (SPEC.md §3). A session
    /// still going after that, which takes a lot of pausing, is ended for the person.
    static let maxSessionSpan: TimeInterval = 8 * 3_600

    let store: SessionStore
    let liveActivities: LiveActivityController?
    /// Snapshots and SwiftUI previews: nothing saved, no ActivityKit, no timers, no analytics.
    let isPreview: Bool
    /// Day boundaries for today's minutes and the streak. Tests set a fixed one.
    var calendar: Calendar = .autoupdatingCurrent
    private let now: () -> Date

    private(set) var stored: StoredSessions
    private var activity: LockinActivity?
    /// Wakes the engine when the running timer ends.
    private(set) var completionTask: Task<Void, Never>?
    /// ActivityKit calls in the order they were made: an update must never overtake the end.
    private var activityWork: Task<Void, Never>?

    public init(
        store: SessionStore = .appGroup(),
        liveActivities: LiveActivityController? = LiveActivityController(),
        now: @escaping () -> Date = Date.init
    ) {
        let loaded = store.load()
        var stored = loaded ?? StoredSessions()
        if !ShortID.isValid(stored.memberID) {
            stored.memberID = ShortID.make()
        }
        self.store = store
        self.liveActivities = liveActivities
        self.now = now
        self.isPreview = false
        self.stored = stored
        _phase = Published(initialValue: SessionEngine.phase(for: stored.active))
        _stats = Published(initialValue: .zero)
        _avatar = Published(initialValue: AvatarCode(stored.avatar))
        _liveActivityProblem = Published(initialValue: nil)

        // The member id has to outlive this launch: it's the `me` of every activity started here.
        if loaded != stored {
            store.save(stored)
        }
        restoreActivity()
        reconcile()
    }

    /// An engine showing `phase` and `stats`, for snapshots and SwiftUI previews. It saves
    /// nothing, never touches ActivityKit and runs no timers; its buttons still change the phase.
    public static func preview(phase: Phase, stats: FocusStats, avatar: AvatarCode) -> SessionEngine {
        SessionEngine(preview: phase, stats: stats, avatar: avatar, liveActivityProblem: nil)
    }

    /// The same, with the Live Activity problem the app explains (Live Activities switched off).
    public static func preview(
        phase: Phase,
        stats: FocusStats,
        avatar: AvatarCode,
        liveActivityProblem: LiveActivityError?
    ) -> SessionEngine {
        SessionEngine(preview: phase, stats: stats, avatar: avatar, liveActivityProblem: liveActivityProblem)
    }

    private init(preview phase: Phase, stats: FocusStats, avatar: AvatarCode, liveActivityProblem: LiveActivityError?) {
        var stored = StoredSessions(avatar: avatar.code, coins: stats.coins, completedSessions: stats.completedSessions)
        switch phase {
        case .running(let startedAt, let endsAt, let plannedMinutes):
            stored.active = ActiveSession(
                id: ShortID.make(), startedAt: startedAt, endsAt: endsAt, pausedAt: nil,
                plannedMinutes: plannedMinutes, version: 1, activityID: nil
            )
        case .paused(let startedAt, let endsAt, let pausedAt, let plannedMinutes):
            stored.active = ActiveSession(
                id: ShortID.make(), startedAt: startedAt, endsAt: endsAt, pausedAt: pausedAt,
                plannedMinutes: plannedMinutes, version: 1, activityID: nil
            )
        case .idle, .finished:
            break
        }
        self.store = .inMemory()
        self.liveActivities = nil
        self.now = { Date() }
        self.isPreview = true
        self.stored = stored
        _phase = Published(initialValue: phase)
        _stats = Published(initialValue: stats)
        _avatar = Published(initialValue: avatar)
        _liveActivityProblem = Published(initialValue: liveActivityProblem)
        analytics = .disabled
    }

    /// This install's member id.
    var memberID: String {
        stored.memberID
    }

    /// The session in progress, as saved.
    var activeSession: ActiveSession? {
        stored.active
    }

    // MARK: - Actions

    /// Starts a session of `minutes`, held to 1...240, with its Live Activity. Does nothing while
    /// a session is running or paused.
    public func start(minutes: Int) {
        switch phase {
        case .running, .paused:
            return
        case .idle, .finished:
            break
        }
        let range = SessionPreset.customRange
        let planned = min(max(minutes, range.lowerBound), range.upperBound)
        let startedAt = now()
        stored.active = ActiveSession(
            id: ShortID.make(),
            startedAt: startedAt,
            endsAt: startedAt.addingTimeInterval(TimeInterval(planned * 60)),
            pausedAt: nil,
            plannedMinutes: planned,
            version: 1,
            activityID: nil
        )
        liveActivityProblem = nil
        startActivity()
        save()
        phase = SessionEngine.phase(for: stored.active)
        scheduleCompletion()
        Log.session.info("Started a \(planned, privacy: .public)-minute session")
    }

    public func pause() {
        guard var session = stored.active, !session.isPaused else { return }
        let time = now()
        guard time < session.endsAt else {
            // The time already ran out: that's a finish, not a pause.
            complete(session)
            return
        }
        session.pausedAt = time
        session.version += 1
        apply(session)
        updateActivity(for: session)
    }

    /// Carries on where the pause left off: the end moves later by the length of the pause.
    public func resume() {
        guard var session = stored.active, let pausedAt = session.pausedAt else { return }
        let time = now()
        session.endsAt = session.endsAt.addingTimeInterval(max(0, time.timeIntervalSince(pausedAt)))
        session.pausedAt = nil
        session.version += 1
        apply(session)
        updateActivity(for: session)
    }

    /// Ends the session early. It's recorded with the minutes focused so far, which pay their
    /// coins; the finishing bonus doesn't. If the time has already run out, it completes instead.
    public func end() {
        guard let session = stored.active else { return }
        let time = now()
        if !session.isPaused, time >= session.endsAt {
            complete(session)
            return
        }
        let focused = session.focusedSeconds(at: time)
        let record = SessionRecord(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: max(time, session.startedAt),
            plannedMinutes: session.plannedMinutes,
            focusedSeconds: focused,
            completed: false,
            coinsEarned: SessionRecord.coins(focusedSeconds: focused, completed: false)
        )
        finish(session, with: record)
    }

    /// Back to idle once the finish has been celebrated.
    public func dismissFinished() {
        if case .finished = phase {
            phase = .idle
        }
    }

    /// Catches up with the clock: finishes a session whose time ran out while the app wasn't
    /// running, rolls today's minutes over at midnight, and starts the Live Activity that couldn't
    /// start before if Live Activities have been switched back on. Call at launch and on every
    /// return to the foreground.
    public func reconcile() {
        guard !isPreview else { return }
        let time = now()
        refreshStats(at: time)
        guard let session = stored.active else {
            if liveActivityProblem == .disabled, liveActivities?.areActivitiesEnabled == true {
                liveActivityProblem = nil
            }
            return
        }
        if !session.isPaused, time >= session.endsAt {
            complete(session)
        } else if time.timeIntervalSince(session.startedAt) >= Self.maxSessionSpan {
            end()
        } else {
            restartActivityIfAllowed()
            scheduleCompletion()
        }
    }

    /// Runs a Live Activity button's command. Set as `SessionIntentBridge.shared.handler` at
    /// launch. Returns once the activity shows the change, so the system doesn't suspend the app
    /// with the update still pending.
    public func handle(_ command: SessionIntentBridge.Command) async {
        // The button may be pressed after the time ran out, before the app noticed.
        reconcile()
        switch command {
        case .pause: pause()
        case .resume: resume()
        case .end: end()
        }
        await activityWork?.value
    }

    // MARK: - Session

    private static func phase(for session: ActiveSession?) -> Phase {
        guard let session else { return .idle }
        if let pausedAt = session.pausedAt {
            return .paused(
                startedAt: session.startedAt,
                endsAt: session.endsAt,
                pausedAt: pausedAt,
                plannedMinutes: session.plannedMinutes
            )
        }
        return .running(startedAt: session.startedAt, endsAt: session.endsAt, plannedMinutes: session.plannedMinutes)
    }

    private func apply(_ session: ActiveSession) {
        stored.active = session
        save()
        phase = SessionEngine.phase(for: session)
        scheduleCompletion()
    }

    private func complete(_ session: ActiveSession) {
        let focused = session.plannedMinutes * 60
        let record = SessionRecord(
            id: session.id,
            startedAt: session.startedAt,
            // When the timer ran out, even if the app only noticed later.
            endedAt: session.endsAt,
            plannedMinutes: session.plannedMinutes,
            focusedSeconds: focused,
            completed: true,
            coinsEarned: SessionRecord.coins(focusedSeconds: focused, completed: true)
        )
        finish(session, with: record)
    }

    private func finish(_ session: ActiveSession, with record: SessionRecord) {
        let isFirstCompletion = record.completed && stored.completedSessions == 0
        stored.active = nil
        stored.append(record)
        stored.coins += record.coinsEarned
        if record.completed {
            stored.completedSessions += 1
        }
        save()
        completionTask?.cancel()
        completionTask = nil
        let time = now()
        refreshStats(at: time)
        phase = .finished(record)
        endActivity(for: session, completed: record.completed, at: time)

        if record.completed {
            analytics.track(.sessionCompleted, counts: ["minutes": record.plannedMinutes, "members": 1])
            if isFirstCompletion {
                analytics.track(.firstSessionCompleted)
            }
        }
        Log.session.info("Session over: \(record.focusedMinutes, privacy: .public) of \(record.plannedMinutes, privacy: .public) minutes, \(record.coinsEarned, privacy: .public) coins")
    }

    /// Sleeps until the running timer ends, then reconciles. Suspended with the app; `reconcile()`
    /// on returning to the foreground covers that.
    private func scheduleCompletion() {
        completionTask?.cancel()
        completionTask = nil
        guard !isPreview, let session = stored.active, !session.isPaused else { return }
        let delay = max(0, session.endsAt.timeIntervalSince(now()))
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            // Reconciling reschedules if the sleep ended a little early.
            self?.reconcile()
        }
    }

    private func avatarChanged(from oldValue: AvatarCode) {
        guard avatar != oldValue else { return }
        stored.avatar = avatar.code
        if var session = stored.active {
            session.version += 1
            stored.active = session
            updateActivity(for: session)
        }
        save()
    }

    private func refreshStats(at time: Date) {
        let fresh = FocusStats.compute(
            history: stored.history,
            coins: stored.coins,
            completedSessions: stored.completedSessions,
            now: time,
            calendar: calendar
        )
        if fresh != stats {
            stats = fresh
        }
    }

    private func save() {
        guard !isPreview else { return }
        store.save(stored)
    }

    // MARK: - Live Activity

    /// The solo activity's content: one member, "You", counting down to `endsAt`.
    func contentState(for session: ActiveSession, showing state: MemberState? = nil) -> LockinAttributes.ContentState {
        let memberState = state ?? (session.isPaused ? .paused : .focusing)
        let member = LockinAttributes.ContentState.Member(
            id: stored.memberID,
            name: Self.soloName,
            avatar: avatar,
            state: memberState,
            // The start moves with the end, so the activity's progress shows time focused rather
            // than time since the first start.
            start: session.endsAt.addingTimeInterval(-session.plannedSeconds),
            end: session.endsAt,
            pausedAt: memberState == .paused ? session.pausedAt : nil
        )
        return LockinAttributes.ContentState(v: session.version, m: [member])
    }

    private func startActivity() {
        guard !isPreview, let controller = liveActivities, var session = stored.active else { return }
        do {
            let started = try controller.start(
                attributes: .solo(me: stored.memberID, sid: session.id),
                state: contentState(for: session),
                now: now()
            )
            activity = started
            session.activityID = started.id
            stored.active = session
            liveActivityProblem = nil
        } catch {
            activity = nil
            liveActivityProblem = LiveActivityError(error)
        }
    }

    /// Picks up the running session's activity after a relaunch, and ends any other: left by a
    /// crash or by a session that ended while the app wasn't running, it would otherwise sit in
    /// the island until the system's 8-hour cap.
    private func restoreActivity() {
        guard let controller = liveActivities else { return }
        let running = controller.activities
        if let id = stored.active?.activityID {
            activity = running.first { $0.id == id }
        }
        let keep = activity?.id
        guard running.contains(where: { $0.id != keep }) else { return }
        enqueueActivityWork {
            _ = await controller.endOrphans(keeping: keep)
        }
    }

    /// Tries the session's Live Activity again when what stopped it may have changed: Live
    /// Activities switched back on in Settings, or the app back in the foreground.
    private func restartActivityIfAllowed() {
        guard activity == nil, let controller = liveActivities, let problem = liveActivityProblem else { return }
        switch problem {
        case .disabled:
            guard controller.areActivitiesEnabled else { return }
        case .notInForeground:
            break
        case .unsupported, .tooMany, .tooLarge, .failed:
            // Trying again won't change these.
            return
        }
        startActivity()
        save()
    }

    private func updateActivity(for session: ActiveSession) {
        guard let controller = liveActivities, let activity else { return }
        let state = contentState(for: session)
        let time = now()
        enqueueActivityWork {
            _ = await controller.update(activity, state: state, now: time)
        }
    }

    private func endActivity(for session: ActiveSession, completed: Bool, at time: Date) {
        guard let controller = liveActivities, let activity else { return }
        self.activity = nil
        var ending = session
        ending.version += 1
        let state = contentState(for: ending, showing: completed ? .done : .left)
        let dismissal: ActivityUIDismissalPolicy
        if completed {
            // On the Lock Screen for 30 minutes after the timer ran out, like the server's `end`
            // push (SPEC.md §4.4); at once if the app only noticed later than that.
            let dismissAt = session.endsAt.addingTimeInterval(LiveActivityLimits.dismissalAfterEndSeconds)
            dismissal = dismissAt > time ? .after(dismissAt) : .immediate
        } else {
            // Ended on purpose, often with the activity's own End button: it goes at once.
            dismissal = .immediate
        }
        enqueueActivityWork {
            await controller.end(activity, state: state, dismissal: dismissal, now: time)
        }
    }

    private func enqueueActivityWork(_ work: @escaping @MainActor () async -> Void) {
        let previous = activityWork
        activityWork = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
