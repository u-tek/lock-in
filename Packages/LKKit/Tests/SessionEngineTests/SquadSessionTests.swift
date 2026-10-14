import API
import Core
import Foundation
import Model
import Testing
@testable import SessionEngine

// Squad mode (docs/milestones/M3.md) with a fake API and no Live Activity controller: the room's
// answers, its live view and `GET /sessions/:id` drive the engine, and the clock only moves when a
// test moves it. Times are minutes after `referenceDate`, when this phone joins.

private func at(minutes: Double) -> Date {
    referenceDate.addingTimeInterval(minutes * 60)
}

@MainActor
@Suite struct SquadStartTests {
    let clock = TestClock(referenceDate)

    @Test func startingAppliesTheServersState() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        #expect(engine.mode == .solo)
        #expect(engine.room == nil)
        #expect(engine.me == engine.memberID)

        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)

        #expect(api.calls == [
            .startSession(squadId: SquadData.squadId, minutes: 25),
            .liveUpdates(SquadData.sessionId),
        ])
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: at(minutes: 25), plannedMinutes: 25))
        #expect(engine.mode == .squad(squadId: SquadData.squadId, sessionId: SquadData.sessionId))
        #expect(engine.mode.isSquad)
        #expect(engine.room == SquadData.room(v: 1, SquadData.mine()))
        #expect(engine.me == SquadData.me)
        #expect(engine.activeSession?.sessionId == SquadData.sessionId)
        #expect(engine.stored.room?.attributes == SquadData.attributes)
        #expect(engine.completionTask != nil)
        #expect(engine.liveTask != nil)
        #expect(engine.squadProblem == nil)
    }

    @Test func minutesAreHeldToOneToFourHours() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 600)
        #expect(api.calls.first == .startSession(squadId: SquadData.squadId, minutes: 240))
    }

    @Test func aRefusalStartsNothing() async throws {
        let refusals: [APIError] = [
            .server(status: 402, code: .plusRequired, message: nil, details: APIErrorDetails(limit: "squads")),
            .server(status: 403, code: .notMember, message: nil),
            .server(status: 409, code: .alreadyInSession, message: nil),
            .offline,
        ]
        for refusal in refusals {
            let store = SessionStore.inMemory()
            let api = FakeSessionAPI { $0.failures["startSession"] = refusal }
            let engine = makeSquadEngine(clock: clock, api: api, store: store)
            await #expect(throws: refusal) {
                try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
            }
            #expect(engine.phase == .idle)
            #expect(engine.mode == .solo)
            #expect(engine.room == nil)
            #expect(engine.activeSession == nil)
            #expect(engine.liveTask == nil)
            #expect(store.load()?.room == nil)
            #expect(api.liveViews == 0)
        }
    }

    @Test func thePaywallLimitComesThrough() async {
        let api = FakeSessionAPI {
            $0.failures["startSession"] = .server(status: 402, code: .plusRequired, message: nil, details: APIErrorDetails(limit: "members"))
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        do {
            try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.plusLimit == "members")
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func withoutAnAPIOrWithASessionRunningNothingStarts() async {
        let solo = makeSquadEngine(clock: clock, api: nil)
        await #expect(throws: APIError.notConfigured) {
            try await solo.startSquad(squadId: SquadData.squadId, minutes: 25)
        }
        #expect(solo.phase == .idle)

        let api = FakeSessionAPI()
        let busy = makeSquadEngine(clock: clock, api: api)
        busy.start(minutes: 25)
        let running = busy.phase
        await #expect(throws: SquadSessionError.sessionInProgress) {
            try await busy.startSquad(squadId: SquadData.squadId, minutes: 25)
        }
        #expect(busy.phase == running)
        #expect(busy.mode == .solo)
        #expect(api.calls.isEmpty)
    }

    @Test func anAnswerWithoutThisPhoneInItIsRefused() async {
        let api = FakeSessionAPI {
            $0.joined = SquadData.joined(LockinAttributes.ContentState(v: 1, m: [SquadData.noorMember()]))
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        await #expect(throws: APIError.invalidResponse) {
            try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        }
        #expect(engine.phase == .idle)
        #expect(engine.stored.room == nil)
    }

    @Test func aTimerTheServerStillRunsIsPickedUpAgain() async throws {
        let api = FakeSessionAPI {
            $0.failures["startSession"] = .server(
                status: 409, code: .alreadyInSession, message: nil, details: APIErrorDetails(sessionId: SquadData.sessionId)
            )
            $0.rejoined = SquadData.joined(SquadData.room(v: 7, SquadData.mine(minutes: 50)))
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        #expect(api.calls == [
            .startSession(squadId: SquadData.squadId, minutes: 25),
            .joinSession(SquadData.sessionId, minutes: 25),
            .liveUpdates(SquadData.sessionId),
        ])
        // Its length is read off the room.
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: at(minutes: 50), plannedMinutes: 50))
        #expect(engine.room?.v == 7)
    }

    @Test func aTimerInAnotherRoomIsLeftToThePerson() async {
        let conflict = APIError.server(status: 409, code: .alreadyInSession, message: nil, details: APIErrorDetails(sessionId: SquadData.sessionId))
        let api = FakeSessionAPI {
            $0.failures["startSession"] = conflict
            $0.rejoined = SquadData.joined(squadId: "SqOtherOne")
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        await #expect(throws: conflict) {
            try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        }
        #expect(engine.phase == .idle)
        #expect(api.liveViews == 0)
    }

    @Test func pushTokensAreUploadedWithTheirEnvironment() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)

        let tokens = AsyncStream<String> { continuation in
            continuation.yield("aa11")
            continuation.yield("bb22")
            continuation.finish()
        }
        await engine.uploadTokens(tokens, sessionId: SquadData.sessionId).value
        #expect(api.count(.uploadToken(SquadData.sessionId, token: "aa11", env: .sandbox)) == 1)
        #expect(api.count(.uploadToken(SquadData.sessionId, token: "bb22", env: .sandbox)) == 1)
        #expect(engine.pendingToken?.token == nil)

        // One that doesn't get through goes again on the next reconcile.
        api.set { $0.failures["uploadToken"] = .offline }
        let failing = AsyncStream<String> { continuation in
            continuation.yield("cc33")
            continuation.finish()
        }
        await engine.uploadTokens(failing, sessionId: SquadData.sessionId).value
        #expect(engine.pendingToken?.token == "cc33")

        api.set { $0.failures = [:] }
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(api.count(.uploadToken(SquadData.sessionId, token: "cc33", env: .sandbox)) == 2)
        #expect(engine.pendingToken?.token == nil)
    }
}

@MainActor
@Suite struct SquadStateTests {
    let clock = TestClock(referenceDate)

    private func started(_ configure: (inout FakeSessionAPI.Answers) -> Void = { _ in }) async throws -> (FakeSessionAPI, SessionEngine) {
        let api = FakeSessionAPI(configure)
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        return (api, engine)
    }

    @Test func myMembersStateDrivesThePhase() async throws {
        let (api, engine) = try await started()

        clock.advance(minutes: 10)
        api.send(.state(status: "open", contentState: SquadData.room(v: 2, SquadData.mine(.paused, pausedAt: at(minutes: 10)))))
        await waitUntil { engine.room?.v == 2 }
        #expect(engine.phase == .paused(startedAt: referenceDate, endsAt: at(minutes: 25), pausedAt: at(minutes: 10), plannedMinutes: 25))
        #expect(engine.completionTask == nil)

        // Resumed after 5 minutes: the end moves.
        clock.advance(minutes: 5)
        api.send(.state(status: "open", contentState: SquadData.room(v: 3, SquadData.mine(pausedFor: 300))))
        await waitUntil { engine.room?.v == 3 }
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: at(minutes: 30), plannedMinutes: 25))
        #expect(engine.completionTask != nil)

        // Done, with Noor still focusing: the finish is recorded, and the room stays.
        clock.advance(minutes: 15)
        api.send(.state(status: "open", contentState: SquadData.room(v: 4, SquadData.mine(.done, pausedFor: 300))))
        await waitUntil { engine.room?.v == 4 }
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        #expect(record.plannedMinutes == 25)
        #expect(record.focusedSeconds == 25 * 60)
        #expect(record.startedAt == referenceDate)
        #expect(record.endedAt == at(minutes: 30))
        #expect(record.coinsEarned == 25 + SessionRecord.completionBonus)
        #expect(engine.stats.coins == 30)
        #expect(engine.stats.completedSessions == 1)
        #expect(engine.activeSession == nil)
        #expect(engine.mode == .squad(squadId: SquadData.squadId, sessionId: SquadData.sessionId))
        #expect(engine.stored.room != nil)
        #expect(engine.liveTask != nil)

        // Squadmates' changes keep coming to the finish screen.
        api.send(.state(status: "open", contentState: SquadData.room(v: 5, SquadData.mine(.done, pausedFor: 300), noor: SquadData.noorMember(.paused))))
        await waitUntil { engine.room?.v == 5 }
        #expect(engine.room?.member(id: SquadData.noor)?.state == .paused)
        #expect(engine.phase.record == record)
    }

    @Test func leavingEarlyIsAPartialFinishAndLetsGoOfTheRoom() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 10)
        api.send(.state(status: "open", contentState: SquadData.room(v: 2, SquadData.mine(.left))))
        await waitUntil { engine.phase.record != nil }
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 10 * 60)
        #expect(record.coinsEarned == 10)
        #expect(record.endedAt == at(minutes: 10))
        #expect(engine.stored.room == nil)
        #expect(engine.liveTask == nil)
        // The last state stays on the finish screen.
        #expect(engine.room?.v == 2)
        #expect(engine.mode.isSquad)
    }

    @Test func slippingIsAPartialFinishButTheRoomStays() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 10)
        api.send(.state(status: "open", contentState: SquadData.room(v: 2, SquadData.mine(.slipped))))
        await waitUntil { engine.phase.record != nil }
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 10 * 60)
        #expect(engine.stored.room != nil)
    }

    @Test func anEndedRoomClosesEverything() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 25)
        let last = SquadData.room(v: 6, SquadData.mine(.done), noor: SquadData.noorMember(.left))
        api.send(.state(status: "ended", contentState: last))
        await waitUntil { engine.phase.record != nil }
        #expect(engine.phase.record?.completed == true)
        #expect(engine.room == last)
        #expect(engine.stored.room == nil)
        #expect(engine.liveTask == nil)
    }

    @Test func anOlderStateNeverRollsTheRoomBack() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 5)
        api.send(.state(status: "open", contentState: SquadData.room(v: 5, SquadData.mine(.paused, pausedAt: at(minutes: 5)))))
        await waitUntil { engine.room?.v == 5 }

        engine.applyRoom(SquadData.room(v: 4, SquadData.mine()), ended: false, sessionId: SquadData.sessionId)
        #expect(engine.room?.v == 5)
        guard case .paused = engine.phase else {
            Issue.record("Expected paused, got \(engine.phase)")
            return
        }
        // Another room's state is no business of this one.
        engine.applyRoom(SquadData.room(v: 9, SquadData.mine(.left)), ended: true, sessionId: "RmSomeOther")
        #expect(engine.room?.v == 5)
        #expect(engine.stored.room != nil)
    }

    @Test func theTimerFinishesOnThisPhonesClock() async throws {
        let (_, engine) = try await started()
        clock.advance(minutes: 25)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        #expect(record.endedAt == at(minutes: 25))
        // Shown done here ahead of the room; same version, so the room's next state replaces it.
        #expect(engine.room?.member(id: SquadData.me)?.state == .done)
        #expect(engine.room?.v == 1)
        #expect(engine.stored.room != nil)

        // The room hasn't caught up yet: its same old state doesn't undo the finish.
        await engine.refreshTask?.value
        #expect(engine.room?.member(id: SquadData.me)?.state == .done)
        #expect(engine.phase.record == record)
    }

    @Test func aDroppedLiveViewWaitsAndTriesAgain() async throws {
        let (api, engine) = try await started()
        api.dropLiveView()
        await waitUntil { engine.liveFailures == 1 }
        #expect(engine.liveFailures == 1)
        // Waiting before the next try.
        #expect(engine.liveTask != nil)
        #expect(engine.isLiveWaiting)
        #expect(api.liveViews == 1)

        // Back in the foreground, it connects again at once.
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(api.liveViews == 2)
        #expect(!engine.isLiveWaiting)
        #expect(engine.liveFailures == 0)
        engine.stopLiveUpdates()
    }

    @Test func dismissingTheFinishGoesBackToSolo() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 25)
        api.send(.state(status: "open", contentState: SquadData.room(v: 2, SquadData.mine(.done))))
        await waitUntil { engine.phase.record != nil }

        engine.dismissFinished()
        #expect(engine.phase == .idle)
        #expect(engine.mode == .solo)
        #expect(engine.room == nil)
        #expect(engine.me == engine.memberID)
        #expect(engine.liveTask == nil)
        // Noor's still focusing: the room's activity stays until the room ends.
        #expect(engine.stored.room != nil)

        // A solo session takes the island: the room lets go.
        engine.start(minutes: 25)
        #expect(engine.stored.room == nil)
        #expect(engine.mode == .solo)
        guard case .running = engine.phase else {
            Issue.record("Expected running, got \(engine.phase)")
            return
        }
    }

    @Test func joiningAgainAfterFinishingCarriesOnInTheSameRoom() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 25)
        api.send(.state(status: "open", contentState: SquadData.room(v: 2, SquadData.mine(.done))))
        await waitUntil { engine.phase.record != nil }

        let again = LockinAttributes.ContentState.Member(
            id: SquadData.me, name: "Ava", avatar: AvatarCode("b1.c1.e1.h1"), state: .focusing,
            start: at(minutes: 25), end: at(minutes: 75)
        )
        api.set { $0.joined = SquadData.joined(SquadData.room(v: 3, again)) }
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 50)
        #expect(engine.phase == .running(startedAt: at(minutes: 25), endsAt: at(minutes: 75), plannedMinutes: 50))
        #expect(engine.room?.v == 3)
        #expect(engine.stats.completedSessions == 1)
        // The live view that was already open carries on.
        #expect(api.liveViews == 1)
    }
}

@MainActor
@Suite struct SquadActionTests {
    let clock = TestClock(referenceDate)

    private func started(_ configure: (inout FakeSessionAPI.Answers) -> Void = { _ in }) async throws -> (FakeSessionAPI, SessionEngine) {
        let api = FakeSessionAPI(configure)
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        return (api, engine)
    }

    @Test func pauseResumeAndEndGoThroughTheRoom() async throws {
        let (api, engine) = try await started {
            $0.states["pause"] = SquadData.room(v: 2, SquadData.mine(.paused, pausedAt: at(minutes: 5)))
            $0.states["resume"] = SquadData.room(v: 3, SquadData.mine(pausedFor: 120))
            $0.states["end"] = SquadData.room(v: 4, SquadData.mine(.left, pausedFor: 120))
        }

        clock.advance(minutes: 5)
        engine.pause()
        // Nothing changes here until the room answers.
        guard case .running = engine.phase else {
            Issue.record("Expected running, got \(engine.phase)")
            return
        }
        await engine.squadWork?.value
        #expect(engine.phase == .paused(startedAt: referenceDate, endsAt: at(minutes: 25), pausedAt: at(minutes: 5), plannedMinutes: 25))
        #expect(engine.room?.v == 2)

        clock.advance(minutes: 2)
        engine.resume()
        await engine.squadWork?.value
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: at(minutes: 27), plannedMinutes: 25))

        clock.advance(minutes: 3)
        engine.end()
        await engine.squadWork?.value
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 8 * 60)
        #expect(engine.stored.room == nil)

        #expect(api.calls == [
            .startSession(squadId: SquadData.squadId, minutes: 25),
            .liveUpdates(SquadData.sessionId),
            .pause(SquadData.sessionId),
            .resume(SquadData.sessionId),
            .end(SquadData.sessionId),
        ])
    }

    @Test func pauseAndResumeOnlyApplyInTheirPhase() async throws {
        let (api, engine) = try await started()
        engine.resume()
        await engine.squadWork?.value
        #expect(!api.calls.contains(.resume(SquadData.sessionId)))
    }

    @Test func slippingGoesThroughTheRoom() async throws {
        let (api, engine) = try await started {
            $0.states["slip"] = SquadData.room(v: 2, SquadData.mine(.slipped))
        }
        clock.advance(minutes: 10)
        engine.slip()
        await engine.squadWork?.value
        #expect(api.calls.last == .slip(SquadData.sessionId))
        #expect(engine.phase.record?.completed == false)
    }

    @Test func theLockScreenButtonsWorkInASquad() async throws {
        let (api, engine) = try await started {
            $0.states["pause"] = SquadData.room(v: 2, SquadData.mine(.paused, pausedAt: at(minutes: 5)))
            $0.states["end"] = SquadData.room(v: 3, SquadData.mine(.left))
        }
        clock.advance(minutes: 5)
        await engine.handle(.pause)
        guard case .paused = engine.phase else {
            Issue.record("Pause should pause, got \(engine.phase)")
            return
        }
        clock.advance(minutes: 10)
        await engine.handle(.end)
        let record = try #require(engine.phase.record)
        // Ended while paused: up to the pause.
        #expect(record.focusedSeconds == 5 * 60)
        #expect(api.calls.contains(.pause(SquadData.sessionId)))
        #expect(api.calls.contains(.end(SquadData.sessionId)))
        // No trip to the server first: the button's own request is the one.
        #expect(!api.calls.contains(.session(SquadData.sessionId)))
    }

    @Test func aButtonAfterTheTimeRanOutJustFinishes() async throws {
        let (api, engine) = try await started()
        clock.advance(minutes: 30)
        await engine.handle(.pause)
        #expect(engine.phase.record?.completed == true)
        #expect(!api.calls.contains(.pause(SquadData.sessionId)))
    }

    @Test func aRoomThatMovedOnIsCaughtUpWith() async throws {
        let (api, engine) = try await started {
            $0.failures["pause"] = .server(status: 409, code: .badState, message: nil)
            $0.snapshot.contentState = SquadData.room(v: 4, SquadData.mine(.paused, pausedAt: at(minutes: 3)))
        }
        clock.advance(minutes: 5)
        engine.pause()
        await engine.squadWork?.value
        #expect(api.calls.contains(.session(SquadData.sessionId)))
        #expect(engine.phase == .paused(startedAt: referenceDate, endsAt: at(minutes: 25), pausedAt: at(minutes: 3), plannedMinutes: 25))
        #expect(engine.squadProblem == nil)
    }

    @Test func aFailedPauseSaysWhyAndChangesNothing() async throws {
        let (_, engine) = try await started { $0.failures["pause"] = .offline }
        engine.pause()
        await engine.squadWork?.value
        #expect(engine.squadProblem == .offline)
        guard case .running = engine.phase else {
            Issue.record("Expected running, got \(engine.phase)")
            return
        }
    }

    @Test func endingOfflineEndsHereAndTellsTheRoomLater() async throws {
        let store = SessionStore.inMemory()
        let api = FakeSessionAPI { $0.failures["end"] = .offline }
        let engine = makeSquadEngine(clock: clock, api: api, store: store)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)

        clock.advance(minutes: 10)
        engine.end()
        await engine.squadWork?.value
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 10 * 60)
        #expect(engine.stored.pendingEnd == SquadData.sessionId)
        #expect(engine.stored.room == nil)
        #expect(engine.room?.member(id: SquadData.me)?.state == .left)

        api.set {
            $0.failures = [:]
            $0.states["end"] = SquadData.room(v: 2, SquadData.mine(.left))
        }
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(api.count(.end(SquadData.sessionId)) == 2)
        #expect(engine.stored.pendingEnd == nil)
        #expect(store.load()?.pendingEnd == nil)
    }

    @Test func anEndTheRoomAlreadyHadIsDoneWith() async throws {
        let api = FakeSessionAPI { $0.failures["end"] = .offline }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        clock.advance(minutes: 10)
        engine.end()
        await engine.squadWork?.value

        // By the time it gets through, the room had finished the timer itself.
        api.set { $0.failures["end"] = .server(status: 409, code: .badState, message: nil) }
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(engine.stored.pendingEnd == nil)
    }

    @Test func cheersGoToTheRoom() async throws {
        let (api, engine) = try await started()
        try await engine.cheer(memberId: SquadData.noor, kind: 3)
        #expect(api.calls.last == .cheer(SquadData.sessionId, to: SquadData.noor, kind: 3))

        api.set {
            $0.failures["cheer"] = .server(status: 429, code: .cheerTooSoon, message: nil, details: APIErrorDetails(retryAfter: 7))
        }
        do {
            try await engine.cheer(memberId: SquadData.noor, kind: 1)
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.retryAfter == 7)
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func cheersNeedASquadSession() async {
        let engine = makeSquadEngine(clock: clock, api: FakeSessionAPI())
        await #expect(throws: SquadSessionError.notInSquadSession) {
            try await engine.cheer(memberId: SquadData.noor, kind: 0)
        }
        let solo = makeSquadEngine(clock: clock, api: nil)
        await #expect(throws: APIError.notConfigured) {
            try await solo.cheer(memberId: SquadData.noor, kind: 0)
        }
    }
}

@MainActor
@Suite struct SquadReconcileTests {
    let clock = TestClock(referenceDate)

    @Test func anEndedRoomFinishesTheSession() async throws {
        let last = SquadData.room(v: 5, SquadData.mine(.done), noor: SquadData.noorMember(.done))
        let api = FakeSessionAPI {
            $0.snapshot = .init(session: SquadData.session(status: SessionInfo.ended), contentState: last)
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)

        // The room finished this timer a little before this phone's clock did.
        clock.advance(minutes: 24.5)
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(api.calls.contains(.session(SquadData.sessionId)))
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        #expect(record.focusedSeconds == 25 * 60)
        #expect(engine.room == last)
        #expect(engine.stored.room == nil)
        #expect(engine.liveTask == nil)
    }

    @Test func aRoomClearedAwayFinishesByTheClock() async throws {
        let api = FakeSessionAPI {
            $0.snapshot = .init(session: SquadData.session(status: SessionInfo.ended), contentState: nil)
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        clock.advance(minutes: 10)
        engine.reconcile()
        await engine.refreshTask?.value
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 10 * 60)
        #expect(engine.stored.room == nil)
    }

    @Test func aRoomThatsGoneFinishesToo() async throws {
        let api = FakeSessionAPI {
            $0.failures["session"] = .server(status: 404, code: .sessionNotFound, message: nil)
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        clock.advance(minutes: 10)
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(engine.phase.record?.completed == false)
        #expect(engine.stored.room == nil)
    }

    @Test func offlineTheTimerCarriesOn() async throws {
        let api = FakeSessionAPI { $0.failures["session"] = .offline }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        clock.advance(minutes: 10)
        engine.reconcile()
        await engine.refreshTask?.value
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: at(minutes: 25), plannedMinutes: 25))
        #expect(engine.stored.room != nil)
    }

    @Test func aSquadSessionSurvivesARelaunch() async throws {
        let store = SessionStore.inMemory()
        let first = makeSquadEngine(clock: clock, api: FakeSessionAPI(), store: store)
        try await first.startSquad(squadId: SquadData.squadId, minutes: 25)
        clock.advance(minutes: 5)

        let api = FakeSessionAPI()
        let second = makeSquadEngine(clock: clock, api: api, store: store)
        #expect(second.mode == .squad(squadId: SquadData.squadId, sessionId: SquadData.sessionId))
        #expect(second.phase == first.phase)
        #expect(second.room == first.room)
        #expect(second.me == SquadData.me)
        #expect(second.activeSession == first.activeSession)
        // It catches up with the room, then watches it.
        await second.refreshTask?.value
        #expect(api.calls == [.session(SquadData.sessionId), .liveUpdates(SquadData.sessionId)])

        // Launched without the API (it comes once the app has made it): the same, once configured.
        let third = SessionEngine(store: store, liveActivities: nil, now: { [clock] in clock.now })
        #expect(third.mode == second.mode)
        #expect(third.refreshTask == nil)
        let later = FakeSessionAPI()
        third.configure(api: later)
        await third.refreshTask?.value
        #expect(later.calls == [.session(SquadData.sessionId), .liveUpdates(SquadData.sessionId)])
    }

    @Test func aSoloSessionNeverAsksTheServer() async {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        engine.start(minutes: 25)
        engine.pause()
        engine.resume()
        engine.reconcile()
        engine.end()
        #expect(engine.refreshTask == nil)
        #expect(api.calls.isEmpty)
        #expect(engine.mode == .solo)
    }

    @Test func eightHoursAfterJoiningTheTimerIsOver() async throws {
        let api = FakeSessionAPI {
            $0.states["pause"] = SquadData.room(v: 2, SquadData.mine(.paused, pausedAt: at(minutes: 10)))
            $0.failures["session"] = .offline
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        clock.advance(minutes: 10)
        engine.pause()
        await engine.squadWork?.value
        clock.advance(minutes: 8 * 60)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 10 * 60)
        #expect(engine.stored.room == nil)
    }
}

@MainActor
@Suite struct SquadPreviewTests {
    @Test func aPreviewShowsTheRoomAndNeverAsks() async throws {
        let room = SquadData.room(v: 3, SquadData.mine())
        let mode = SessionMode.squad(squadId: SquadData.squadId, sessionId: SquadData.sessionId)
        let engine = SessionEngine.preview(phase: .idle, stats: .zero, avatar: .default, mode: mode, room: room, me: SquadData.me)
        #expect(engine.isPreview)
        #expect(engine.mode == mode)
        #expect(engine.room == room)
        #expect(engine.me == SquadData.me)

        try await engine.startSquad(squadId: SquadData.squadId, minutes: 50)
        guard case .running(_, _, 50) = engine.phase else {
            Issue.record("Expected running, got \(engine.phase)")
            return
        }
        #expect(engine.mode.squadId == SquadData.squadId)
        #expect(engine.room == room)
        try await engine.cheer(memberId: SquadData.noor, kind: 2)
        engine.pause()
        guard case .paused = engine.phase else {
            Issue.record("Expected paused, got \(engine.phase)")
            return
        }
        engine.end()
        #expect(engine.phase.record != nil)
        engine.dismissFinished()
        #expect(engine.mode == .solo)
        #expect(engine.store.load() == nil)
    }

    @Test func theModeSaysWhoseSessionItIs() {
        let squad = SessionMode.squad(squadId: "SqA", sessionId: "RmA")
        #expect(squad.isSquad)
        #expect(squad.squadId == "SqA")
        #expect(squad.sessionId == "RmA")
        #expect(!SessionMode.solo.isSquad)
        #expect(SessionMode.solo.squadId == nil)
        #expect(SessionMode.solo.sessionId == nil)
    }
}
