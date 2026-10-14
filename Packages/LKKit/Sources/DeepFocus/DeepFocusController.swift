import Foundation

/// Deep Focus from the app's side: shields that follow the session, and the slips to send.
///
/// Call it alongside the session engine, only when the person has Plus, has Deep Focus on, and
/// `DeepFocusAuthorization.status` is `.approved`; it doesn't check any of those itself.
///
/// - Session starts: `start(sessionEnds:sessionID:withSquad:)`.
/// - Pause, resume (with the moved end), finish or leave: `pause()`, `resume(sessionEnds:)`,
///   `stop()`.
/// - Launch and every return to the foreground: `reconcile()`, then send `drainSlips()`. If the
///   session engine has no session running but `sessionID` isn't nil (the app was killed and the
///   session finished meanwhile), call `stop()`.
/// - The person changes their apps: save with `DeepFocusSelection`, then `selectionDidChange()`.
@MainActor
public final class DeepFocusController: ObservableObject {
    /// The session being shielded (or paused), as recorded in the App Group.
    @Published public private(set) var sessionID: String? = nil
    /// Whether the chosen apps are shielded right now.
    @Published public private(set) var isShielding = false

    let engine: DeepFocusEngine
    private let now: () -> Date

    /// The real thing: ManagedSettings and DeviceActivity, on the App Group's files.
    public convenience init(storage: DeepFocusStorage = .appGroup()) {
        self.init(engine: .live(storage: storage), now: Date.init)
    }

    init(engine: DeepFocusEngine, now: @escaping () -> Date) {
        self.engine = engine
        self.now = now
        publish(engine.currentState())
    }

    /// One that never touches ManagedSettings or DeviceActivity, for snapshots and previews. Its
    /// files are in a temporary directory of its own.
    public static func preview() -> DeepFocusController {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepFocusPreview-\(UUID().uuidString)", isDirectory: true)
        let engine = DeepFocusEngine(
            storage: DeepFocusStorage(directory: directory),
            shields: InertShields(),
            monitor: InertMonitoring()
        )
        return DeepFocusController(engine: engine, now: Date.init)
    }

    /// Shields the chosen apps until `sessionEnds`. Replaces any session recorded before.
    ///
    /// - Parameters:
    ///   - sessionID: The session's id. For a squad session use the server's: slips are sent with
    ///     `POST /sessions/:id/slip` against it.
    ///   - withSquad: Whether friends are in it; the shield says "Your squad's still going."
    @discardableResult
    public func start(sessionEnds: Date, sessionID: String, withSquad: Bool = false) -> DeepFocusStartOutcome {
        let outcome = engine.start(sessionID: sessionID, endsAt: sessionEnds, withSquad: withSquad, now: now())
        publish(engine.currentState())
        return outcome
    }

    /// Lifts the shields for the pause. Any "Open anyway" grace ends with it.
    public func pause() {
        engine.pause(now: now())
        publish(engine.currentState())
    }

    /// Shields again until the session's new end. `.ended` when no session was recorded (call
    /// `start` instead) or the new end has passed.
    @discardableResult
    public func resume(sessionEnds: Date) -> DeepFocusStartOutcome {
        let outcome = engine.resume(endsAt: sessionEnds, now: now())
        publish(engine.currentState())
        return outcome
    }

    /// Lifts every shield and forgets the session: it finished, the person left, or Deep Focus was
    /// switched off. Safe to call when nothing is running.
    public func stop() {
        engine.stop(now: now())
        publish(engine.currentState())
    }

    /// Puts the shields right: down if the session ended while Lockin wasn't running, up (less any
    /// grace) if it's still going.
    public func reconcile() {
        engine.sync(now: now())
        publish(engine.currentState())
    }

    /// The person saved a new choice of apps: shield it now if a session is running.
    public func selectionDidChange() {
        reconcile()
    }

    /// The slips recorded since the last drain, oldest first, taken out of the inbox. Send each
    /// with `POST /sessions/:id/slip`; put back any that didn't go with `SlipInbox.append(contentsOf:)`.
    public func drainSlips() -> [Slip] {
        engine.slips.drain()
    }

    private func publish(_ state: DeepFocusState) {
        let shielding = state.isShielding(at: now()) && engine.shields.hasSelection
        if sessionID != state.session?.id {
            sessionID = state.session?.id
        }
        if isShielding != shielding {
            isShielding = shielding
        }
    }
}
