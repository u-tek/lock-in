// SessionEngine in a squad (M3, docs/milestones/M3.md): the session runs in a room on the server.
//
// The room is the authority for every member's timer, this phone's included. Starting asks the
// server (`POST /sessions`), which answers with the Live Activity's attributes and content-state;
// the engine starts the activity with them, uploads each of its push tokens, and opens the room's
// live view (a WebSocket). From then on every state the room sends, whether as the answer to an
// action, over the live view or from `GET /sessions/:id`, is applied three ways: to `room` for
// the session screen, to the Live Activity (Apple recommends updating it from the app as well as
// by push), and to `phase`, from this phone's member in it.
//
// The local timer still finishes the session on time without the server, as solo does: the room
// marks the member done at the same moment and says so a little later.
//
// When this phone's timer is done but squadmates are still focusing, the room's Live Activity
// stays: the server keeps pushing to it and ends it, with everyone's final state, when the last
// member finishes. Leaving early ends it here at once.

import ActivityKit
import API
import Core
import Foundation
import LiveActivity
import Model

/// Whose session the engine is running.
public enum SessionMode: Equatable, Sendable {
    case solo
    /// A squad's room: `sessionId` is the room (`LockinAttributes.sid`).
    case squad(squadId: String, sessionId: String)

    public var isSquad: Bool {
        switch self {
        case .solo: return false
        case .squad: return true
        }
    }

    public var squadId: String? {
        switch self {
        case .solo: return nil
        case .squad(let squadId, _): return squadId
        }
    }

    public var sessionId: String? {
        switch self {
        case .solo: return nil
        case .squad(_, let sessionId): return sessionId
        }
    }
}

/// Why a squad session couldn't start or a cheer couldn't go, besides the server's own answers
/// (which throw `APIError`).
public enum SquadSessionError: Error, Equatable, Sendable, LocalizedError {
    /// A session is already running, paused or starting on this phone: end it first.
    case sessionInProgress
    /// There's no squad session to do that in.
    case notInSquadSession

    public var errorDescription: String? {
        switch self {
        case .sessionInProgress: return "You're already in a session. End it first."
        case .notInSquadSession: return "You're not in a squad session."
        }
    }
}

extension SessionEngine {
    enum SquadAction: Equatable {
        case pause, resume, end, slip
    }

    // MARK: - Squad sessions

    /// Gives the engine the Lockin API, or takes it away (nil: solo only). Call at launch, before
    /// the Live Activity's buttons can reach the engine. A squad session restored from the last
    /// launch catches up with its room straight away.
    public func configure(api: (any LockinAPI)?) {
        self.api = api
        guard !isPreview else { return }
        guard api != nil else {
            stopLiveUpdates()
            return
        }
        refreshRoom()
    }

    /// Locks in with a squad: joins its open room, or opens one (`POST /sessions`). Once the
    /// server has answered, the session runs here as it does solo, with the room's Live Activity.
    ///
    /// Throws, and starts nothing here, when the server says no: `APIError` (`plusRequired`,
    /// `notMember`, `alreadyInSession` with `sessionId`, `offline`, `notConfigured` without an
    /// API, …), or `SquadSessionError.sessionInProgress` while a session is running or starting.
    public func startSquad(squadId: String, minutes: Int) async throws {
        switch phase {
        case .running, .paused:
            throw SquadSessionError.sessionInProgress
        case .idle, .finished:
            break
        }
        guard !isStartingSquad else { throw SquadSessionError.sessionInProgress }
        let planned = Self.clampedMinutes(minutes)
        if isPreview {
            startPreviewSquad(squadId: squadId, minutes: planned)
            return
        }
        guard let api else { throw APIError.notConfigured }
        isStartingSquad = true
        defer { isStartingSquad = false }
        // An end the server never heard would otherwise stand in the way (409 already_in_session).
        await flushPendingEnd()
        let (joined, recovered) = try await join(squadId: squadId, minutes: planned, api: api)
        try adopt(joined, squadId: squadId, plannedMinutes: recovered ? nil : planned)
        analytics.track(.squadSessionJoined)
    }

    /// Joins a squad's room by its id (`POST /sessions/:id/join`): Join 25 or Join 50 on an "is
    /// locking in" alert (M4). Once the server has answered, the session runs as `startSquad`'s
    /// does. Already in that room, it does nothing.
    ///
    /// A room that has closed since the alert went out (`session_ended`, `session_not_found`)
    /// doesn't stop anyone locking in: the squad's open room is joined instead, or a new one
    /// opened, as `startSquad` does.
    ///
    /// - Parameter pushToStart: the push-to-start spike's token, for a join from the background:
    ///   the server starts the Live Activity by push, and the engine takes up the one iOS starts
    ///   (`watchPushedActivities()`). If the server couldn't, the activity starts here instead,
    ///   next time the app is in the foreground.
    /// - Returns: whether the server push-started the Live Activity.
    @discardableResult
    public func joinSquadSession(
        sessionId: String,
        squadId: String,
        minutes: Int,
        pushToStart: PushToStart? = nil
    ) async throws -> Bool {
        if let session = stored.active, session.sessionId == sessionId {
            return false
        }
        switch phase {
        case .running, .paused:
            throw SquadSessionError.sessionInProgress
        case .idle, .finished:
            break
        }
        guard !isStartingSquad else { throw SquadSessionError.sessionInProgress }
        let planned = Self.clampedMinutes(minutes)
        if isPreview {
            startPreviewSquad(squadId: squadId, minutes: planned)
            return false
        }
        guard let api else { throw APIError.notConfigured }
        isStartingSquad = true
        defer { isStartingSquad = false }
        await flushPendingEnd()
        // Still showing this room's activity (finished in it, joining again): a push-to-start
        // would start a second one.
        let token = roomActivity?.attributes.sid == sessionId ? nil : pushToStart
        let joined: JoinedSession
        let recovered: Bool
        do {
            joined = try await api.joinSession(id: sessionId, minutes: planned, pushToStart: token)
            recovered = false
        } catch let error as APIError where error.code == .sessionEnded || error.code == .sessionNotFound {
            Log.session.info("The alert's room has closed; locking in with the squad instead")
            let started = try await join(squadId: squadId, minutes: planned, pushToStart: token, api: api)
            joined = started.0
            recovered = started.recovered
        }
        let pushed = token != nil && joined.pushedToStart == true
        try adopt(
            joined,
            squadId: joined.session.squadId ?? squadId,
            plannedMinutes: recovered ? nil : planned,
            startsActivity: !pushed
        )
        analytics.track(.squadSessionJoined)
        return pushed
    }

    /// Cheers a squadmate in the room (`kind` 0–7, an index into the cheer emoji). The cheer
    /// reaches everyone, this phone included, with the room's next state. Throws `APIError`
    /// (`cheerTooSoon` with `retryAfter`, …) or `SquadSessionError.notInSquadSession`.
    public func cheer(memberId: String, kind: Int) async throws {
        guard !isPreview else { return }
        guard let api else { throw APIError.notConfigured }
        guard let link = stored.room else { throw SquadSessionError.notInSquadSession }
        try await api.cheer(sessionId: link.sessionId, to: memberId, kind: kind)
    }

    // MARK: - Starting

    /// `POST /sessions` for the squad. A 409 `already_in_session` means the server still runs a
    /// timer this phone lost track of (a reinstall, or a crash at the wrong moment): when it's in
    /// this squad's room it's picked up again (joining while running answers with the same
    /// timer), otherwise the 409 stands, for the person to deal with.
    private func join(
        squadId: String,
        minutes: Int,
        pushToStart: PushToStart? = nil,
        api: any LockinAPI
    ) async throws -> (JoinedSession, recovered: Bool) {
        do {
            let joined = try await api.startSession(squadId: squadId, minutes: minutes, pushToStart: pushToStart)
            return (joined, false)
        } catch let error as APIError where error.code == .alreadyInSession {
            guard let sessionId = error.sessionId,
                  sessionId != stored.pendingEnd,
                  let joined = try? await api.joinSession(id: sessionId, minutes: minutes, pushToStart: pushToStart),
                  joined.session.squadId == squadId
            else { throw error }
            Log.session.info("Picked up a squad session the server was still running")
            return (joined, true)
        }
    }

    /// Takes on the room the server put this phone in: the timer, the Live Activity, its push
    /// tokens and the live view. `plannedMinutes` is nil for a timer picked up again, whose
    /// length is read off the room. `startsActivity` is false when the server has started the
    /// Live Activity by push (M4 spike): the engine takes up that one instead.
    func adopt(_ joined: JoinedSession, squadId: String, plannedMinutes: Int?, startsActivity: Bool = true) throws {
        let attributes = joined.attributes
        let state = joined.contentState
        guard let mine = state.member(id: attributes.me), mine.isActive else {
            throw APIError.invalidResponse
        }
        // One session in the island: a room this phone finished in earlier lets go of it.
        if let link = stored.room, link.sessionId != attributes.sid {
            leaveRoom(dismissal: .immediate)
        }
        var link = stored.room ?? RoomLink(squadId: squadId, attributes: attributes, state: state, activityID: nil)
        if state.v >= link.state.v {
            link.state = state
        }
        stored.room = link
        let planned = plannedMinutes ?? Self.minutes(of: mine)
        stored.active = ActiveSession(
            id: ShortID.make(),
            startedAt: mine.startDate,
            endsAt: mine.endDate,
            pausedAt: mine.state == .paused ? (mine.pausedDate ?? now()) : nil,
            plannedMinutes: planned,
            version: link.state.v,
            activityID: nil,
            sessionId: attributes.sid
        )
        liveActivityProblem = nil
        squadProblem = nil
        if startsActivity {
            startRoomActivity()
        } else {
            takeUpPushedRoomActivity()
        }
        save()
        phase = Self.phase(for: stored.active)
        mode = .squad(squadId: link.squadId, sessionId: link.sessionId)
        show(room: link.state, me: link.me)
        scheduleCompletion()
        startTokenUploads()
        liveFailures = 0
        openLiveUpdates()
        Log.session.info("Joined a squad session for \(planned, privacy: .public) minutes")
    }

    private func startPreviewSquad(squadId: String, minutes: Int) {
        let shown = room
        let shownMe = roomMe
        start(minutes: minutes)
        mode = .squad(squadId: squadId, sessionId: "PreviewRm1")
        show(room: shown, me: shownMe)
    }

    // MARK: - Applying the room's state

    /// Applies a state of the room, from wherever it came: an action's answer, the live view, or
    /// `GET /sessions/:id`. Only a newer version replaces the one held: the room never sends two
    /// different states with the same `v`, and an equal one would undo a change made here ahead
    /// of the room (a timer that ran out on this phone's clock). This phone's member is then read
    /// from whichever is newest. `ended`: the room is over (nobody's timer is running), so this
    /// phone's part in it is too.
    func applyRoom(_ incoming: LockinAttributes.ContentState?, ended: Bool, sessionId: String) {
        guard var link = stored.room, link.sessionId == sessionId else { return }
        if let incoming, incoming.v > link.state.v {
            link.state = incoming
            stored.room = link
            updateRoomActivity(with: incoming)
        }
        if isShowing(sessionId) {
            show(room: link.state, me: link.me)
        }
        if let session = stored.active, session.sessionId == sessionId {
            follow(session, in: link, ended: ended)
        }
        if ended {
            closeRoom(sessionId: sessionId)
        } else if stored.active?.sessionId != sessionId, let current = stored.room, current.sessionId == sessionId,
                  current.mine == nil || current.mine?.state == .left {
            // This phone has left the room: the server stops updating its activity, so it goes.
            leaveRoom(dismissal: .immediate)
        } else {
            save()
        }
    }

    /// Moves this phone's timer to where its member is in the room.
    private func follow(_ session: ActiveSession, in link: RoomLink, ended: Bool) {
        let time = now()
        let timeIsUp = !session.isPaused && time >= session.endsAt
        guard let mine = link.mine else {
            // Not in the room's state any more: whatever happened, this timer is over.
            finishSquadTimer(session, completed: timeIsUp, at: time)
            return
        }
        switch mine.state {
        case .focusing, .onBreak, .paused, .slipped:
            // A slip doesn't stop the timer: it shows for 5 minutes while it runs (decision 0009).
            if ended {
                // A room that's over can't still be running this timer: finish it by the clock.
                finishSquadTimer(session, completed: timeIsUp, at: time)
                return
            }
            var updated = session
            updated.startedAt = mine.startDate
            updated.endsAt = mine.endDate
            updated.pausedAt = mine.state == .paused ? (mine.pausedDate ?? session.pausedAt ?? time) : nil
            updated.version = link.state.v
            if updated != session {
                apply(updated)
            }
        case .done:
            finishSquadTimer(session, completed: true, at: time)
        case .left:
            finishSquadTimer(session, completed: false, at: time)
        }
    }

    /// Records this phone's squad timer as finished: completed, with the planned minutes, or
    /// stopped early with the minutes focused so far. Coins and stats as solo.
    func finishSquadTimer(_ session: ActiveSession, completed: Bool, at time: Date) {
        let focused = completed ? session.plannedMinutes * 60 : session.focusedSeconds(at: time)
        let record = SessionRecord(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: completed ? session.endsAt : max(time, session.startedAt),
            plannedMinutes: session.plannedMinutes,
            focusedSeconds: focused,
            completed: completed,
            coinsEarned: SessionRecord.coins(focusedSeconds: focused, completed: completed)
        )
        finish(session, with: record, members: max(1, stored.room?.state.m.count ?? 1))
    }

    /// The timer ran out on this phone's clock: it's finished here at once, and shown done in the
    /// room and on the activity until the room says so itself.
    func completeSquadLocally(_ session: ActiveSession) {
        if let sessionId = session.sessionId, var link = stored.room, link.sessionId == sessionId {
            link.state = Self.marking(link.me, as: .done, in: link.state)
            stored.room = link
            updateRoomActivity(with: link.state)
            if isShowing(sessionId) {
                show(room: link.state, me: link.me)
            }
        }
        finishSquadTimer(session, completed: true, at: now())
    }

    /// The clock's part of `reconcile()` for a squad timer: a timer that ran out finishes, one
    /// past the 8-hour cap is over (the room makes it "left" then too), and otherwise the
    /// activity gets another chance to start.
    func reconcileSquadTimer(_ session: ActiveSession, at time: Date) {
        guard let link = stored.room, link.sessionId == session.sessionId else {
            // A squad timer without its room: nothing can follow it any more.
            finishSquadTimer(session, completed: !session.isPaused && time >= session.endsAt, at: time)
            return
        }
        if !session.isPaused, time >= session.endsAt {
            completeSquadLocally(session)
        } else if time.timeIntervalSince(session.startedAt) >= Self.maxSessionSpan {
            finishSquadTimer(session, completed: false, at: time)
            leaveRoom(dismissal: .immediate)
        } else {
            restartRoomActivityIfAllowed()
            scheduleCompletion()
        }
    }

    // MARK: - Actions

    func enqueueSquadAction(_ action: SquadAction) {
        guard !isPreview else { return }
        let previous = squadWork
        squadWork = Task { @MainActor in
            await previous?.value
            await self.perform(action)
        }
    }

    /// Sends one action to the room and applies its answer. The timer's state is checked again
    /// first: earlier actions may have moved it on.
    func perform(_ action: SquadAction) async {
        guard let session = stored.active, let sessionId = session.sessionId else { return }
        switch action {
        case .pause:
            guard !session.isPaused else { return }
        case .resume:
            guard session.isPaused else { return }
        case .end, .slip:
            break
        }
        guard let api else {
            if action == .end {
                endSquadLocally(session, sessionId: sessionId)
            } else {
                squadProblem = .notConfigured
            }
            return
        }
        do {
            let state: LockinAttributes.ContentState
            switch action {
            case .pause: state = try await api.pauseSession(id: sessionId)
            case .resume: state = try await api.resumeSession(id: sessionId)
            case .end: state = try await api.endSession(id: sessionId)
            case .slip: state = try await api.slipSession(id: sessionId)
            }
            squadProblem = nil
            // The room ends as soon as nobody's timer is running. A slip's answer shows this
            // member slipped with the timer still running, so `follow` keeps it going.
            let ended = !state.m.contains(where: { $0.isActive })
            applyRoom(state, ended: ended, sessionId: sessionId)
        } catch is CancellationError {
            return
        } catch let error as APIError {
            switch error.code {
            case .badState?, .sessionEnded?, .sessionNotFound?, .notMember?:
                // The room has moved on without this phone: catch up with it.
                await refreshRoomNow()
            default:
                if action == .end, Self.isConnectivity(error), let current = stored.active, current.sessionId == sessionId {
                    endSquadLocally(current, sessionId: sessionId)
                } else {
                    squadProblem = error
                }
            }
        } catch {
            squadProblem = .invalidResponse
        }
    }

    /// The End button with no way to reach the server: the session ends here all the same, and
    /// the room hears about it on the next chance (`pendingEnd`). A timer whose time was up just
    /// completes: the room finishes it on its own.
    func endSquadLocally(_ session: ActiveSession, sessionId: String) {
        let time = now()
        if !session.isPaused, time >= session.endsAt {
            completeSquadLocally(session)
            return
        }
        stored.pendingEnd = sessionId
        if var link = stored.room, link.sessionId == sessionId {
            link.state = Self.marking(link.me, as: .left, in: link.state)
            stored.room = link
            if isShowing(sessionId) {
                show(room: link.state, me: link.me)
            }
        }
        finishSquadTimer(session, completed: false, at: time)
        leaveRoom(dismissal: .immediate)
    }

    // MARK: - Catching up with the server

    /// Starts catching up with the room in the background, unless that's already under way or
    /// there's nothing to catch up on.
    func refreshRoom() {
        guard !isPreview, api != nil, refreshTask == nil else { return }
        guard stored.room != nil || stored.pendingEnd != nil || pendingToken != nil else { return }
        refreshTask = Task { @MainActor in
            await self.refreshRoomNow()
            self.refreshTask = nil
        }
    }

    /// Sends what couldn't be sent before, reads the room (`GET /sessions/:id`) and applies it,
    /// then (re)opens the live view while the session screen is showing. Offline, the local timer
    /// carries on.
    func refreshRoomNow() async {
        guard let api else { return }
        await flushPendingEnd()
        await retryPendingToken()
        guard let link = stored.room else { return }
        let sessionId = link.sessionId
        do {
            let snapshot = try await api.session(id: sessionId)
            // A null state: the ended room has been cleared away (a day after it ended).
            let ended = snapshot.session.isEnded || snapshot.contentState == nil
            applyRoom(snapshot.contentState, ended: ended, sessionId: sessionId)
        } catch let error as APIError where error.code == .sessionNotFound || error.code == .notMember {
            // The room is gone, or this phone's account isn't in it any more.
            applyRoom(nil, ended: true, sessionId: sessionId)
        } catch {
            return
        }
        if isLiveWaiting {
            // Back in the foreground: no need to sit out the rest of the wait.
            stopLiveUpdates()
            liveFailures = 0
        }
        openLiveUpdates()
    }

    /// Tells the room about an end made offline. Done once the room answers, or says the timer
    /// had already stopped; anything else is tried again later.
    func flushPendingEnd() async {
        guard let api, let sessionId = stored.pendingEnd else { return }
        do {
            _ = try await api.endSession(id: sessionId)
        } catch let error as APIError {
            switch error.code {
            case .badState?, .sessionEnded?, .sessionNotFound?, .notMember?:
                break
            default:
                return
            }
        } catch {
            return
        }
        if stored.pendingEnd == sessionId {
            stored.pendingEnd = nil
            save()
        }
    }

    private func retryPendingToken() async {
        guard let pending = pendingToken else { return }
        guard stored.room?.sessionId == pending.sessionId else {
            pendingToken = nil
            return
        }
        await upload(token: pending.token, sessionId: pending.sessionId)
    }

    // MARK: - The live view

    /// Opens the room's WebSocket while its session screen is showing (mode squad). Each state is
    /// applied as it comes; a dropped connection is tried again after a wait that grows to a
    /// minute.
    func openLiveUpdates() {
        guard !isPreview, liveTask == nil, let api, let link = stored.room, isShowing(link.sessionId) else { return }
        let sessionId = link.sessionId
        let updates = api.liveUpdates(sessionId: sessionId)
        liveTask = Task { @MainActor [weak self] in
            do {
                for try await message in updates {
                    guard let self else { return }
                    self.liveFailures = 0
                    if case .state(let status, let state) = message {
                        self.applyRoom(state, ended: status == SessionInfo.ended, sessionId: sessionId)
                    }
                }
            } catch {
                // Dropped: offline, suspended in the background, or turned down.
            }
            guard let self, !Task.isCancelled else { return }
            self.liveTask = nil
            self.reconnectLiveUpdates(sessionId: sessionId)
        }
    }

    private func reconnectLiveUpdates(sessionId: String) {
        guard let link = stored.room, link.sessionId == sessionId, isShowing(sessionId) else { return }
        liveFailures += 1
        let delay = min(60, 1 << min(liveFailures, 6))
        isLiveWaiting = true
        liveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.liveTask = nil
            self.isLiveWaiting = false
            self.openLiveUpdates()
        }
    }

    func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        isLiveWaiting = false
    }

    // MARK: - The room's Live Activity

    /// Starts the room's activity with the server's attributes and state, or carries on with the
    /// one already running for the same room (joining again after finishing).
    func startRoomActivity() {
        guard !isPreview, let controller = liveActivities, var link = stored.room else { return }
        if let running = roomActivity, running.attributes.sid == link.sessionId {
            updateRoomActivity(with: link.state)
            return
        }
        if let pushed = pushedRoomActivity(in: controller) {
            // iOS started it already, from the server's push-to-start (M4 spike).
            attachRoomActivity(pushed)
            return
        }
        do {
            let started = try controller.start(attributes: link.attributes, state: link.state, now: now())
            roomActivity = started
            link.activityID = started.id
            stored.room = link
            liveActivityProblem = nil
        } catch {
            roomActivity = nil
            liveActivityProblem = LiveActivityError(error)
        }
    }

    /// Tries the room's activity again when what stopped it may have changed, as solo does.
    private func restartRoomActivityIfAllowed() {
        guard roomActivity == nil, stored.room != nil, let controller = liveActivities, let problem = liveActivityProblem else { return }
        switch problem {
        case .disabled:
            guard controller.areActivitiesEnabled else { return }
        case .notInForeground:
            break
        case .unsupported, .tooMany, .tooLarge, .failed:
            return
        }
        startRoomActivity()
        save()
        startTokenUploads()
    }

    func updateRoomActivity(with state: LockinAttributes.ContentState) {
        guard let controller = liveActivities, let activity = roomActivity else { return }
        let time = now()
        enqueueActivityWork {
            // Skipped when the activity already shows a newer version (a push got there first).
            _ = await controller.update(activity, state: state, now: time)
        }
    }

    /// The room is over for this phone: it ended, this phone left it, or another session takes
    /// the island. The live view and token uploads stop, the link goes, and the activity ends
    /// with the room's last state: at once, or after `dismissal` (nil: 30 minutes, like the
    /// server's `end` push).
    func leaveRoom(dismissal: ActivityUIDismissalPolicy?) {
        guard let link = stored.room else { return }
        stopLiveUpdates()
        tokenTask?.cancel()
        tokenTask = nil
        if pendingToken?.sessionId == link.sessionId {
            pendingToken = nil
        }
        stored.room = nil
        save()
        guard let controller = liveActivities, let activity = roomActivity else { return }
        roomActivity = nil
        let state = link.state
        let time = now()
        enqueueActivityWork {
            await controller.end(activity, state: state, dismissal: dismissal, now: time)
        }
    }

    /// The room has ended. Its activity stays on the Lock Screen for 30 minutes with everyone's
    /// final state, or goes at once if this phone had left.
    private func closeRoom(sessionId: String) {
        guard let link = stored.room, link.sessionId == sessionId else { return }
        if link.mine?.state == .left {
            leaveRoom(dismissal: .immediate)
        } else {
            leaveRoom(dismissal: nil)
        }
    }

    // MARK: - Activities started by push (M4 spike)

    /// After a join whose Live Activity the server push-started: takes up the activity if iOS
    /// has already started it, else waits for `watchPushedActivities()` to see it arrive. Until
    /// it does, coming to the foreground starts one here instead (`reconcile()` treats it as an
    /// activity that couldn't start in the background), and a late arrival then ends.
    func takeUpPushedRoomActivity() {
        guard !isPreview, let link = stored.room else { return }
        if let running = roomActivity, running.attributes.sid == link.sessionId {
            updateRoomActivity(with: link.state)
            return
        }
        if let controller = liveActivities, let pushed = pushedRoomActivity(in: controller) {
            attachRoomActivity(pushed)
            return
        }
        liveActivityProblem = .notInForeground
    }

    /// Watches, for as long as the engine lives, for Live Activities the system starts by push,
    /// and takes up the room's. iOS wakes the app in the background for one, so its push token
    /// reaches the server even when the app wasn't running.
    func watchPushedActivities() {
        guard !isPreview, liveActivities != nil, pushedActivityTask == nil else { return }
        pushedActivityTask = Task { @MainActor [weak self] in
            for await activity in LockinActivity.activityUpdates {
                guard let self else { return }
                self.takeUp(pushed: activity)
            }
        }
    }

    /// One activity the system started. The room's becomes the room's activity, with its push
    /// tokens uploaded as for one started here; a second one for the same room (the push came
    /// after the app started its own) ends. Anything else, such as the admin's push-to-start
    /// test, is left alone.
    func takeUp(pushed started: LockinActivity) {
        guard started.activityState != .ended, started.activityState != .dismissed else { return }
        guard let link = stored.room, started.attributes.sid == link.sessionId else { return }
        if let current = roomActivity {
            guard current.id != started.id, let controller = liveActivities else { return }
            Log.liveActivity.info("Ended a second activity for the room")
            enqueueActivityWork {
                await controller.end(started, state: nil, dismissal: .immediate)
            }
            return
        }
        attachRoomActivity(started)
        save()
        startTokenUploads()
        Log.liveActivity.info("Took up the room's activity, started by push")
    }

    /// A running activity for the room that the engine hasn't taken up yet.
    private func pushedRoomActivity(in controller: LiveActivityController) -> LockinActivity? {
        guard let link = stored.room else { return nil }
        return controller.activities.first { candidate in
            candidate.attributes.sid == link.sessionId && candidate.id != activity?.id && candidate.id != roomActivity?.id
        }
    }

    /// Makes `started` the room's activity and brings it up to the room's latest state: the push
    /// carried the state of the moment it was sent. The caller saves and starts the token
    /// uploads.
    private func attachRoomActivity(_ started: LockinActivity) {
        guard var link = stored.room else { return }
        roomActivity = started
        link.activityID = started.id
        stored.room = link
        liveActivityProblem = nil
        updateRoomActivity(with: link.state)
    }

    // MARK: - Push tokens

    /// Uploads each push token of the room's activity, as it arrives and whenever it changes.
    func startTokenUploads() {
        tokenTask?.cancel()
        tokenTask = nil
        guard !isPreview, let controller = liveActivities, let activity = roomActivity, let link = stored.room else { return }
        tokenTask = uploadTokens(controller.pushTokens(of: activity), sessionId: link.sessionId)
    }

    /// Uploads every token from `tokens` for the session (`POST /sessions/:id/la-token`), with
    /// this build's APNs environment.
    func uploadTokens(_ tokens: AsyncStream<String>, sessionId: String) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await token in tokens {
                guard let self else { return }
                await self.upload(token: token, sessionId: sessionId)
            }
        }
    }

    func upload(token: String, sessionId: String) async {
        guard let api else {
            pendingToken = (sessionId: sessionId, token: token)
            return
        }
        do {
            try await api.uploadLiveActivityToken(sessionId: sessionId, token: token, env: pushEnvironment)
            if pendingToken?.token == token {
                pendingToken = nil
            }
        } catch is CancellationError {
            return
        } catch {
            // Without it the room can't push to this phone: tried again on the next reconcile.
            pendingToken = (sessionId: sessionId, token: token)
            Log.liveActivity.error("Couldn't upload the room activity's push token")
        }
    }

    // MARK: - Helpers

    /// Shows the room on the session screen, with this phone's member in it.
    func show(room state: LockinAttributes.ContentState?, me: String?) {
        if room != state {
            room = state
        }
        roomMe = me
    }

    /// Back to showing solo: no room.
    func showSolo() {
        if mode != .solo {
            mode = .solo
        }
        show(room: nil, me: nil)
    }

    /// The session screen is showing this room.
    func isShowing(_ sessionId: String) -> Bool {
        mode.sessionId == sessionId
    }

    /// Minutes held to 1...240 (SPEC.md §1.4), as the server takes them.
    static func clampedMinutes(_ minutes: Int) -> Int {
        let range = SessionPreset.customRange
        return min(max(minutes, range.lowerBound), range.upperBound)
    }

    /// The length of a member's timer, for one picked up again without its planned minutes: its
    /// span, which includes any pauses so far.
    static func minutes(of member: LockinAttributes.ContentState.Member) -> Int {
        let span = (member.e - member.b) / 60
        guard span.isFinite else { return SessionPreset.customRange.lowerBound }
        return clampedMinutes(Int(span.rounded()))
    }

    /// `state` with a member's state changed here, ahead of the room saying so. The version stays:
    /// the room's next state replaces it.
    static func marking(
        _ memberId: String,
        as memberState: MemberState,
        in state: LockinAttributes.ContentState
    ) -> LockinAttributes.ContentState {
        guard let index = state.m.firstIndex(where: { $0.i == memberId }) else { return state }
        var marked = state
        marked.m[index].state = memberState
        marked.m[index].q = nil
        return marked
    }

    /// The squad session a saved store was in the middle of, for a relaunch.
    static func restoredSquad(
        _ stored: StoredSessions
    ) -> (mode: SessionMode, state: LockinAttributes.ContentState, me: String)? {
        guard let link = stored.room, let active = stored.active, active.sessionId == link.sessionId else { return nil }
        return (mode: SessionMode.squad(squadId: link.squadId, sessionId: link.sessionId), state: link.state, me: link.me)
    }

    static func isConnectivity(_ error: APIError) -> Bool {
        switch error {
        case .offline, .network:
            return true
        default:
            return false
        }
    }
}
