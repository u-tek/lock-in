import Foundation

/// How starting (or resuming) Deep Focus for a session went.
public enum DeepFocusStartOutcome: Equatable, Sendable {
    /// Shields are up, and a DeviceActivity schedule lifts them when the session ends even if
    /// Lockin isn't running.
    case shielding
    /// Shields are up, but DeviceActivity refused the schedule. Lockin lifts them itself
    /// (`DeepFocusController.stop()` when the session ends, `reconcile()` at launch), and a shield
    /// left up after the session offers to unlock.
    case shieldingWhileLockinRuns
    /// No apps chosen, so nothing is shielded. The session is still recorded, so choosing apps
    /// mid-session (`selectionDidChange()`) shields them.
    case nothingSelected
    /// The session has already ended (or ends within a minute): nothing to do.
    case ended
}

/// A shield's button, without ManagedSettings' `ShieldAction`.
public enum DeepFocusShieldButton: Sendable {
    /// "Back to focus", or "Unlock" on a shield left over from a finished session.
    case primary
    /// "Open anyway".
    case secondary
}

/// What the system should do after a shield button (ManagedSettings' `ShieldActionResponse`).
public enum DeepFocusShieldResponse: Equatable, Sendable {
    /// `.close`: close the app. "Back to focus".
    case closeApp
    /// `.defer`: redraw the shield. The app is no longer shielded by then, so it opens.
    case redrawShield
    /// `.none`: leave the shield as it is.
    case keepShield
}

/// The one place that decides what's shielded: the app and all three extensions go through it.
///
/// The app records the session (`start`, `pause`, `resume`, `stop`); every process may then bring
/// the shields in line with what's recorded (`sync`). The extensions never apply or clear shields
/// blindly: an `intervalDidEnd` can arrive because the app rescheduled, not because the session
/// ended, so each callback reads the state and does what it says. The worst a stray callback can do
/// is repeat what's already true.
///
/// A change to the state and the shields happens under `state.lock`, so the app and an extension
/// acting at once can't leave the shields from an older state. DeviceActivity calls are made after
/// the lock is released: stopping a schedule calls the monitor extension, which takes the lock too.
public struct DeepFocusEngine {
    /// How long "Open anyway" lets an app through before shielding it again.
    public static let graceLength: TimeInterval = 5 * 60

    let storage: DeepFocusStorage
    let shields: any DeepFocusShielding
    let monitor: any DeepFocusMonitoring
    let slips: SlipInbox

    init(storage: DeepFocusStorage, shields: any DeepFocusShielding, monitor: any DeepFocusMonitoring) {
        self.storage = storage
        self.shields = shields
        self.monitor = monitor
        self.slips = SlipInbox(storage: storage)
    }

    /// ManagedSettings and DeviceActivity, on the App Group's files. What the extensions use.
    public static func live(storage: DeepFocusStorage = .appGroup()) -> DeepFocusEngine {
        DeepFocusEngine(
            storage: storage,
            shields: ManagedSettingsShields(selection: DeepFocusSelection(storage: storage)),
            monitor: DeviceActivityMonitoring()
        )
    }

    // MARK: - The session (app)

    /// Shields the chosen apps until `endsAt`, replacing any session recorded before.
    func start(sessionID: String, endsAt: Date, withSquad: Bool, now: Date) -> DeepFocusStartOutcome {
        guard endsAt.timeIntervalSince(now) > DeepFocusState.tolerance else {
            stop(now: now)
            return .ended
        }
        update(now: now) { state in
            state.session = DeepFocusState.Session(
                id: sessionID,
                endsAt: endsAt.timeIntervalSince1970,
                isPaused: false,
                withSquad: withSquad
            )
            state.graces = []
        }
        return scheduleSession(endingAt: endsAt, now: now)
    }

    /// Lifts the shields while the session is paused. Graces end with the pause.
    func pause(now: Date) {
        update(now: now) { state in
            state.session?.isPaused = true
            state.graces = []
        }
        monitor.stopMonitoring([.session])
    }

    /// Shields again until the session's new end (a pause moves it later).
    func resume(endsAt: Date, now: Date) -> DeepFocusStartOutcome {
        var hadSession = false
        update(now: now) { state in
            guard state.session != nil else { return }
            hadSession = true
            state.session?.isPaused = false
            state.session?.endsAt = endsAt.timeIntervalSince1970
        }
        guard hadSession, endsAt.timeIntervalSince(now) > DeepFocusState.tolerance else {
            stop(now: now)
            return .ended
        }
        return scheduleSession(endingAt: endsAt, now: now)
    }

    /// Lifts every shield and forgets the session. Safe to call when nothing is running.
    func stop(now: Date) {
        update(now: now) { state in
            state.session = nil
            state.graces = []
        }
        monitor.stopMonitoring([.session, .grace])
    }

    private func scheduleSession(endingAt end: Date, now: Date) -> DeepFocusStartOutcome {
        let outcome: DeepFocusStartOutcome
        if let schedule = DeepFocusSchedule.ending(at: end, now: now) {
            do {
                try monitor.startMonitoring(.session, during: schedule)
                outcome = .shielding
            } catch {
                deepFocusLog.error("DeviceActivity refused the session schedule: \(String(describing: error), privacy: .public)")
                outcome = .shieldingWhileLockinRuns
            }
        } else {
            outcome = .ended
        }
        return shields.hasSelection ? outcome : .nothingSelected
    }

    // MARK: - Any process

    /// Brings the shields and the grace timer in line with the recorded state: up while a session
    /// runs (less the apps on a grace), down otherwise. What every extension callback does.
    public func sync(now: Date = Date()) {
        update(now: now)
    }

    /// The recorded state. Read without the lock: the file is replaced whole, never rewritten.
    func currentState() -> DeepFocusState {
        SharedFile.read(DeepFocusState.self, from: storage.stateURL) ?? DeepFocusState()
    }

    // MARK: - Shield extensions

    /// A button on the shield, for the shield action extension.
    ///
    /// - "Back to focus" closes the app.
    /// - "Open anyway" records a slip, lets `token` through for `graceLength`, and redraws the
    ///   shield, which is gone by then. Without a token there's nothing to let through: the slip
    ///   still counts and the shield stays.
    /// - Either, on a shield left up after the session (no callback reached the monitor in time),
    ///   takes every shield down.
    public func handleShieldAction(
        _ button: DeepFocusShieldButton,
        target: DeepFocusShieldTarget,
        token: Data?,
        now: Date = Date()
    ) -> DeepFocusShieldResponse {
        let state = currentState()
        guard state.isShielding(at: now), let session = state.session else {
            sync(now: now)
            return .redrawShield
        }
        switch button {
        case .primary:
            return .closeApp
        case .secondary:
            do {
                try slips.append(Slip(sessionID: session.id, at: now.timeIntervalSince1970))
            } catch {
                deepFocusLog.error("Couldn't record a slip")
            }
            guard let token else { return .keepShield }
            update(now: now) { state in
                state.graces.removeAll { $0.target == target && $0.token == token }
                state.graces.append(DeepFocusState.Grace(
                    target: target,
                    token: token,
                    until: now.timeIntervalSince1970 + Self.graceLength
                ))
            }
            return .redrawShield
        }
    }

    /// What the shield says, for the shield configuration extension: "You're locked in" during a
    /// session, or an unlock offer on a shield left up after one.
    public func shieldContent(appName: String?, now: Date = Date()) -> ShieldContent {
        let state = currentState()
        guard state.isShielding(at: now), let session = state.session else {
            return .lifted(appName: appName)
        }
        return .locked(appName: appName, withSquad: session.withSquad)
    }

    // MARK: - Applying the state

    private enum GraceTimerChange {
        case start(endingAt: Double)
        case stop
    }

    /// Changes the state, then makes the shields match it, under the lock; then starts or stops
    /// the grace timer outside it.
    @discardableResult
    private func update(now: Date, _ change: (inout DeepFocusState) -> Void = { _ in }) -> DeepFocusState {
        var timerChange: GraceTimerChange?
        let state = locked { () -> DeepFocusState in
            var state = currentState()
            let before = state
            change(&state)
            state.pruneGraces(at: now)

            if state.isShielding(at: now), shields.hasSelection {
                shields.shield(except: state.graces)
            } else {
                shields.clear()
            }

            let wantedEnd = state.isShielding(at: now) ? state.nextGraceEnd : nil
            if wantedEnd != state.graceTimerEnd {
                timerChange = wantedEnd.map { GraceTimerChange.start(endingAt: $0) } ?? .stop
                state.graceTimerEnd = wantedEnd
            }

            if state != before {
                save(state)
            }
            return state
        }

        switch timerChange {
        case .start(let end)?:
            guard let schedule = DeepFocusSchedule.ending(at: Date(timeIntervalSince1970: end), now: now) else { break }
            do {
                try monitor.startMonitoring(.grace, during: schedule)
            } catch {
                // Not recorded as set, so the next sync tries again. Until then the app stays
                // unshielded; the session's end or the app's next launch puts that right.
                deepFocusLog.error("DeviceActivity refused the grace schedule: \(String(describing: error), privacy: .public)")
                locked {
                    var current = currentState()
                    if current.graceTimerEnd == end {
                        current.graceTimerEnd = nil
                        save(current)
                    }
                }
            }
        case .stop?:
            monitor.stopMonitoring([.grace])
        case nil:
            break
        }
        return state
    }

    private func save(_ state: DeepFocusState) {
        do {
            try storage.prepare()
            try SharedFile.write(state, to: storage.stateURL)
        } catch {
            deepFocusLog.error("Couldn't save the Deep Focus state")
        }
    }

    /// Runs `body` holding `state.lock`, or without it when the lock file can't be opened (the
    /// state is still replaced whole, so a reader never sees half of it).
    private func locked<T>(_ body: () -> T) -> T {
        do {
            try storage.prepare()
            return try SharedFile.withLock(storage.stateLockURL) { _ in body() }
        } catch {
            deepFocusLog.error("Couldn't lock the Deep Focus state; going ahead")
            return body()
        }
    }
}
