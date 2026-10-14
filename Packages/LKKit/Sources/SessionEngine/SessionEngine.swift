// SessionEngine: the local session. Timer state, coins and streaks, persistence, and the Live
// Activity that mirrors it. App only: the widget extension never runs a session.
//
// Times are stored as dates, not ticks: the timer is `endsAt`, and the Live Activity counts down
// to it on its own with `Text(timerInterval:)`. Nothing here runs once a second.
//
// Solo sessions live here; squad sessions (M3), which run in a room on the server, are in
// SessionEngine+Squad.swift.

import ActivityKit
import API
import Combine
import Core
import Foundation
import LiveActivity
import Model

/// Runs one session at a time, solo or in a squad's room, and keeps the stats Home shows.
///
/// Every change is saved straight away, so a session survives the app being suspended, killed or
/// woken in the background by a Live Activity button. Call `reconcile()` at launch and whenever
/// the app comes to the foreground: a session whose time ran out meanwhile finishes then, and a
/// squad session catches up with its room.
@MainActor
public final class SessionEngine: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(startedAt: Date, endsAt: Date, plannedMinutes: Int)
        case paused(startedAt: Date, endsAt: Date, pausedAt: Date, plannedMinutes: Int)
        case finished(SessionRecord)
    }

    @Published public internal(set) var phase: Phase
    @Published public internal(set) var stats: FocusStats
    /// Saved when set. Mid-session, a solo Live Activity picks it up too (a squad room keeps the
    /// Lockling it was joined with).
    @Published public var avatar: AvatarCode {
        didSet { avatarChanged(from: oldValue) }
    }
    /// Why the current session has no Live Activity, if it hasn't. The session runs regardless;
    /// the app explains, and links to Settings for `.disabled`.
    @Published public internal(set) var liveActivityProblem: LiveActivityError?
    /// Whose session `phase` is: solo, or a squad's room. Squad from `startSquad` (or a relaunch
    /// mid-session) through the finish, until `dismissFinished()` or the next start.
    @Published public internal(set) var mode: SessionMode
    /// The squad's latest state while `mode` is squad, for the session screen: every member's
    /// timer, the pet and the latest cheer, live over the room's WebSocket. It keeps the final
    /// state through the finish. Nil when solo.
    @Published public internal(set) var room: LockinAttributes.ContentState?
    /// Why the last squad action (pause, resume, end, a Lock Screen button) didn't go through.
    /// Nil once one does. Starting a squad session throws instead.
    @Published public internal(set) var squadProblem: APIError?

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
    let now: () -> Date

    var stored: StoredSessions
    /// The solo session's Live Activity.
    var activity: LockinActivity?
    /// Wakes the engine when the running timer ends.
    var completionTask: Task<Void, Never>?
    /// ActivityKit calls in the order they were made: an update must never overtake the end.
    var activityWork: Task<Void, Never>?

    // Squad sessions (SessionEngine+Squad.swift).

    /// The Lockin API, for squad sessions. Nil: solo only.
    var api: (any LockinAPI)?
    /// The squad room's Live Activity.
    var roomActivity: LockinActivity?
    /// This phone's member id in `room`, kept alongside it.
    var roomMe: String?
    /// The room's live view (its WebSocket), or the wait before connecting again.
    var liveTask: Task<Void, Never>?
    /// Live view connections lost in a row, for the wait before the next one.
    var liveFailures = 0
    /// Uploads the room activity's push tokens as they arrive.
    var tokenTask: Task<Void, Never>?
    /// A push token the server hasn't got yet, tried again on `reconcile()`.
    var pendingToken: (sessionId: String, token: String)?
    /// Squad actions, one at a time in the order they were made.
    var squadWork: Task<Void, Never>?
    /// Catching up with the server (`reconcile()`).
    var refreshTask: Task<Void, Never>?
    /// `startSquad` is waiting for the server.
    var isStartingSquad = false
    /// The APNs host the room's push tokens belong to. Tests set one.
    var pushEnvironment: APNsEnvironment = .current

    /// - Parameters:
    ///   - liveActivities: The controller that mirrors the session as a Live Activity, or nil for
    ///     none (tests). No default: `LiveActivityController()` is main-actor isolated, and a
    ///     default argument is evaluated outside the actor in this Swift 5 mode module.
    ///   - api: The Lockin API for squad sessions; nil for solo only. `configure(api:)` sets it
    ///     later.
    public init(
        store: SessionStore = .appGroup(),
        liveActivities: LiveActivityController?,
        api: (any LockinAPI)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let loaded = store.load()
        var stored = loaded ?? StoredSessions()
        if !ShortID.isValid(stored.memberID) {
            stored.memberID = ShortID.make()
        }
        let squad = SessionEngine.restoredSquad(stored)
        self.store = store
        self.liveActivities = liveActivities
        self.api = api
        self.now = now
        self.isPreview = false
        self.stored = stored
        _phase = Published(initialValue: SessionEngine.phase(for: stored.active))
        _stats = Published(initialValue: .zero)
        _avatar = Published(initialValue: AvatarCode(stored.avatar))
        _liveActivityProblem = Published(initialValue: nil)
        _mode = Published(initialValue: squad?.mode ?? .solo)
        _room = Published(initialValue: squad?.state)
        _squadProblem = Published(initialValue: nil)
        roomMe = squad?.me

        // The member id has to outlive this launch: it's the `me` of every activity started here.
        if loaded != stored {
            store.save(stored)
        }
        restoreActivity()
        if roomActivity != nil {
            // Tokens can change while the app isn't running: the current one goes up again.
            startTokenUploads()
        }
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

    /// An engine in a squad session, for snapshots and SwiftUI previews: `room` is the squad's
    /// state and `me` this phone's member in it. Like the solo preview, it saves nothing and its
    /// buttons only change the phase.
    public static func preview(
        phase: Phase,
        stats: FocusStats,
        avatar: AvatarCode,
        mode: SessionMode,
        room: LockinAttributes.ContentState?,
        me: String,
        liveActivityProblem: LiveActivityError? = nil
    ) -> SessionEngine {
        let engine = SessionEngine(preview: phase, stats: stats, avatar: avatar, liveActivityProblem: liveActivityProblem)
        engine.mode = mode
        engine.room = room
        engine.roomMe = me
        return engine
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
        _mode = Published(initialValue: .solo)
        _room = Published(initialValue: nil)
        _squadProblem = Published(initialValue: nil)
        analytics = .disabled
    }

    /// This install's member id: the `me` of a solo session.
    var memberID: String {
        stored.memberID
    }

    /// This phone's member id in `room`: the account's user id in a squad session, this
    /// install's own id when solo.
    public var me: String {
        roomMe ?? stored.memberID
    }

    /// The session in progress, as saved.
    var activeSession: ActiveSession? {
        stored.active
    }

    // MARK: - Actions

    /// Starts a solo session of `minutes`, held to 1...240, with its Live Activity. Does nothing
    /// while a session is running, paused or starting. (`startSquad` starts one in a squad.)
    public func start(minutes: Int) {
        switch phase {
        case .running, .paused:
            return
        case .idle, .finished:
            break
        }
        guard !isStartingSquad else { return }
        // One session in the island: a squad room this phone finished in lets go of it.
        leaveRoom(dismissal: .immediate)
        showSolo()
        let planned = Self.clampedMinutes(minutes)
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

    /// Pauses the running timer. In a squad, the room is asked and its answer applied.
    public func pause() {
        if let session = stored.active, session.isSquad {
            if !session.isPaused {
                enqueueSquadAction(.pause)
            }
            return
        }
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
        if let session = stored.active, session.isSquad {
            if session.isPaused {
                enqueueSquadAction(.resume)
            }
            return
        }
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
    /// In a squad, the room is asked; offline, the session ends here and the room hears later.
    public func end() {
        if let session = stored.active, session.isSquad {
            enqueueSquadAction(.end)
            return
        }
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

    /// Breaks focus on purpose: Deep Focus (M8) calls this when a shielded app is opened. In a
    /// squad, the room shows it (state 5, "slipped"); solo, it ends the session early.
    public func slip() {
        guard let session = stored.active else { return }
        if session.isSquad {
            enqueueSquadAction(.slip)
        } else {
            end()
        }
    }

    /// Back to idle once the finish has been celebrated. A squad session's screen closes with it:
    /// the mode goes back to solo, and the room's live view stops (its Live Activity stays while
    /// squadmates are still focusing, until the room ends).
    public func dismissFinished() {
        guard case .finished = phase else { return }
        phase = .idle
        if mode != .solo || room != nil {
            showSolo()
            stopLiveUpdates()
        }
    }

    /// Catches up with the clock: finishes a session whose time ran out while the app wasn't
    /// running, rolls today's minutes over at midnight, and starts the Live Activity that couldn't
    /// start before if Live Activities have been switched back on. Call at launch and on every
    /// return to the foreground.
    ///
    /// In a squad it also catches up with the room (`GET /sessions/:id`, then its live view), and
    /// sends what couldn't be sent before: an end made offline, a push token.
    public func reconcile() {
        guard !isPreview else { return }
        let time = now()
        refreshStats(at: time)
        refreshRoom()
        if let session = stored.active, session.isSquad {
            reconcileSquadTimer(session, at: time)
            return
        }
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
        if let session = stored.active, session.isSquad {
            // The clock only: the button's own request is the trip to the server.
            if !isPreview {
                reconcileSquadTimer(session, at: now())
            }
        } else {
            reconcile()
        }
        switch command {
        case .pause: pause()
        case .resume: resume()
        case .end: end()
        }
        await squadWork?.value
        await activityWork?.value
    }

    // MARK: - Session

    static func phase(for session: ActiveSession?) -> Phase {
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

    func apply(_ session: ActiveSession) {
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

    /// Records the finished session and shows it. `members` counts who was in the room, for
    /// analytics (1 when solo).
    func finish(_ session: ActiveSession, with record: SessionRecord, members: Int = 1) {
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
            analytics.track(.sessionCompleted, counts: ["minutes": record.plannedMinutes, "members": members])
            if isFirstCompletion {
                analytics.track(.firstSessionCompleted)
            }
        }
        Log.session.info("Session over: \(record.focusedMinutes, privacy: .public) of \(record.plannedMinutes, privacy: .public) minutes, \(record.coinsEarned, privacy: .public) coins")
    }

    /// Sleeps until the running timer ends, then reconciles. Suspended with the app; `reconcile()`
    /// on returning to the foreground covers that.
    func scheduleCompletion() {
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
        // A squad room has the Lockling its member joined with; only a solo activity follows.
        if var session = stored.active, !session.isSquad {
            session.version += 1
            stored.active = session
            updateActivity(for: session)
        }
        save()
    }

    func refreshStats(at time: Date) {
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

    func save() {
        guard !isPreview else { return }
        store.save(stored)
    }

    // MARK: - Live Activity

    /// Whether the activity with this ActivityKit id is the engine's own: the solo session's, or
    /// the squad room's. Anything else running at launch is an orphan.
    public func ownsActivity(id: String) -> Bool {
        activity?.id == id || roomActivity?.id == id
    }

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

    /// Picks up the running session's activity (or the squad room's) after a relaunch, and ends
    /// any other: left by a crash or by a session that ended while the app wasn't running, it
    /// would otherwise sit in the island until the system's 8-hour cap.
    private func restoreActivity() {
        guard let controller = liveActivities else { return }
        let running = controller.activities
        if let id = stored.active?.activityID {
            activity = running.first { $0.id == id }
        }
        if let id = stored.room?.activityID {
            roomActivity = running.first { $0.id == id }
        }
        let keep = activity?.id ?? roomActivity?.id
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

    func enqueueActivityWork(_ work: @escaping @MainActor () async -> Void) {
        let previous = activityWork
        activityWork = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
