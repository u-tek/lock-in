import Combine
import Core
import DeepFocus
import Foundation
import Paywall
import SessionEngine

/// Keeps Deep Focus in step with the session (docs/milestones/M8.md).
///
/// - Shields go up when a session runs, for someone with Plus who has Deep Focus on and Screen
///   Time approved; they come down for a pause and go back up after it; they're lifted when the
///   session finishes or any of those stops being true.
/// - The shield shows the person's Lockling, so it's stored whenever it changes.
/// - At launch and on every return to the foreground (`didBecomeActive()`), Screen Time's status
///   is read again, the shields are put right, and the slips recorded by "Open anyway" while
///   Lockin wasn't running are collected. A slip in the squad session running now goes to the
///   room (`SessionEngine.slip()`), once per batch; any other is moot by now and dropped.
@MainActor
final class DeepFocusCoordinator {
    let models: DeepFocusModels
    private let engine: SessionEngine
    private let plus: PlusStore
    /// What the controller was last told, so an unchanged session isn't sent again.
    private var applied: Shielding?
    private var subscriptions: Set<AnyCancellable> = []

    init(engine: SessionEngine, plus: PlusStore, models: DeepFocusModels = DeepFocusModels()) {
        self.engine = engine
        self.plus = plus
        self.models = models
        ShieldIcon.storeAvatar(engine.avatar)
        didBecomeActive()
        watch()
    }

    /// Launch and every return to the foreground: Screen Time may have been switched off in
    /// Settings, the session may have ended while Lockin wasn't running, and the shield may have
    /// recorded slips.
    func didBecomeActive() {
        models.authorization.refresh()
        models.controller.reconcile()
        sync(phase: engine.phase, mode: engine.mode, isAllowed: isAllowed)
        sendSlips()
    }

    // MARK: - Following the session

    /// A session as the shields see it.
    private struct Shielding: Equatable {
        var sessionID: String
        var endsAt: Date
        var isPaused: Bool
        var withSquad: Bool

        /// Nil unless a session is running or paused.
        init?(phase: SessionEngine.Phase, mode: SessionMode) {
            let startedAt: Date
            switch phase {
            case .running(let started, let ends, _):
                startedAt = started
                endsAt = ends
                isPaused = false
            case .paused(let started, let ends, _, _):
                startedAt = started
                endsAt = ends
                isPaused = true
            case .idle, .finished:
                return nil
            }
            // A squad's slips go to its room, so the shields use the room's id. A solo session has
            // none on the server; its slips stay on the phone.
            sessionID = mode.sessionId ?? "solo-\(Int(startedAt.timeIntervalSince1970))"
            withSquad = mode.sessionId != nil
        }
    }

    private var isAllowed: Bool {
        Self.allows(isPlus: plus.isPlus, isOn: models.isOn, status: models.authorization.status)
    }

    /// Nonisolated: Combine's operators run it.
    private nonisolated static func allows(isPlus: Bool, isOn: Bool, status: DeepFocusAuthorization.Status) -> Bool {
        isPlus && isOn && status == .approved
    }

    /// `@Published` sends a new value before the property holds it, so everything here works from
    /// the values sent, never from the models.
    private func watch() {
        let session = engine.$phase.combineLatest(engine.$mode)
        let allowed = Publishers.CombineLatest3(plus.$isPlus, models.$isOn, models.authorization.$status)
            .map { isPlus, isOn, status in
                DeepFocusCoordinator.allows(isPlus: isPlus, isOn: isOn, status: status)
            }
            .removeDuplicates()
        session.combineLatest(allowed)
            .sink { [weak self] session, isAllowed in
                guard let self else { return }
                let (phase, mode) = session
                // `@Published` sends on the main thread here: the engine, the store and the models
                // are all main-actor objects.
                MainActor.assumeIsolated {
                    self.sync(phase: phase, mode: mode, isAllowed: isAllowed)
                }
            }
            .store(in: &subscriptions)

        engine.$avatar
            .removeDuplicates()
            .dropFirst()
            .sink { avatar in
                ShieldIcon.storeAvatar(avatar)
            }
            .store(in: &subscriptions)
    }

    private func sync(phase: SessionEngine.Phase, mode: SessionMode, isAllowed: Bool) {
        let controller = models.controller
        guard isAllowed, let target = Shielding(phase: phase, mode: mode) else {
            applied = nil
            if controller.sessionID != nil {
                controller.stop()
            }
            return
        }
        let previous = applied
        guard target != previous || controller.sessionID != target.sessionID else { return }
        applied = target

        guard controller.sessionID == target.sessionID else {
            // A new session, or Deep Focus switched on mid-session.
            let outcome = controller.start(sessionEnds: target.endsAt, sessionID: target.sessionID, withSquad: target.withSquad)
            if target.isPaused {
                controller.pause()
            }
            Log.app.info("Deep Focus started: \(String(describing: outcome), privacy: .public)")
            return
        }
        if target.isPaused {
            controller.pause()
        } else if let previous, previous.sessionID == target.sessionID, !previous.isPaused, previous.endsAt == target.endsAt {
            // Nothing moved: just put the shields right.
            controller.reconcile()
        } else {
            // Out of a pause (the end moved with it), a squad's end moved, or the first look at
            // this session since launch: shield until the end the session has now.
            controller.resume(sessionEnds: target.endsAt)
        }
    }

    // MARK: - Slips

    /// Collects the slips the shield recorded. A slip in the squad session running now shows in
    /// the room (once for the whole batch: the room shows a slip for 5 minutes either way); any
    /// other is from a session that's over, or solo, with nobody to show it to.
    private func sendSlips() {
        let slips = models.controller.drainSlips()
        guard !slips.isEmpty else { return }
        let squadSession = engine.mode.sessionId
        let toSquad = squadSession != nil && slips.contains { $0.sessionID == squadSession }
        if toSquad {
            engine.slip()
        }
        AppServices.analytics.track(.deepFocusSlip, counts: ["slips": slips.count, "squad": toSquad ? 1 : 0])
    }
}
