import API
import Core
import Foundation
import Model
import Testing
@testable import SessionEngine

// Join 25 and Join 50 on an "is locking in" alert (docs/milestones/M4.md): the engine joins the
// alert's room by its id, with the push-to-start spike's token when the join runs in the
// background. A fake API and no Live Activity controller, as in SquadSessionTests.

@MainActor
@Suite struct JoinFromAlertTests {
    let clock = TestClock(referenceDate)

    private func join(
        _ engine: SessionEngine,
        minutes: Int = 25,
        pushToStart: PushToStart? = nil
    ) async throws -> Bool {
        try await engine.joinSquadSession(
            sessionId: SquadData.sessionId,
            squadId: SquadData.squadId,
            minutes: minutes,
            pushToStart: pushToStart
        )
    }

    @Test func joinsTheAlertsRoom() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)

        let pushed = try await join(engine)

        #expect(!pushed)
        #expect(api.calls == [
            .joinSession(SquadData.sessionId, minutes: 25),
            .liveUpdates(SquadData.sessionId),
        ])
        #expect(api.pushToStarts == [nil])
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: referenceDate.addingTimeInterval(25 * 60), plannedMinutes: 25))
        #expect(engine.mode == .squad(squadId: SquadData.squadId, sessionId: SquadData.sessionId))
        #expect(engine.me == SquadData.me)
        #expect(engine.stored.room?.sessionId == SquadData.sessionId)
        #expect(engine.liveActivityProblem == nil)
    }

    @Test func minutesAreHeldToOneToFourHours() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        _ = try await join(engine, minutes: 0)
        #expect(api.calls.first == .joinSession(SquadData.sessionId, minutes: 1))
    }

    @Test func alreadyInThatRoomNothingHappens() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        try await engine.startSquad(squadId: SquadData.squadId, minutes: 25)
        let before = api.calls

        let pushed = try await join(engine, minutes: 50)

        #expect(!pushed)
        #expect(api.calls == before)
        #expect(engine.phase == .running(startedAt: referenceDate, endsAt: referenceDate.addingTimeInterval(25 * 60), plannedMinutes: 25))
    }

    @Test func anotherSessionStandsInTheWay() async {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        engine.start(minutes: 25)
        let running = engine.phase
        await #expect(throws: SquadSessionError.sessionInProgress) {
            try await engine.joinSquadSession(sessionId: SquadData.sessionId, squadId: SquadData.squadId, minutes: 25)
        }
        #expect(engine.phase == running)
        #expect(engine.mode == .solo)
        #expect(api.calls.isEmpty)
    }

    @Test func aClosedRoomLocksInWithTheSquadInstead() async throws {
        for code in [APIErrorCode.sessionEnded, .sessionNotFound] {
            let api = FakeSessionAPI {
                $0.failures["joinSession"] = .server(status: code == .sessionEnded ? 410 : 404, code: code, message: nil)
            }
            let engine = makeSquadEngine(clock: clock, api: api)

            _ = try await join(engine)

            #expect(api.calls == [
                .joinSession(SquadData.sessionId, minutes: 25),
                .startSession(squadId: SquadData.squadId, minutes: 25),
                .liveUpdates(SquadData.sessionId),
            ])
            #expect(engine.mode.isSquad)
            #expect(engine.phase != .idle)
        }
    }

    @Test func aRefusalStartsNothing() async {
        let refusals: [APIError] = [
            .server(status: 403, code: .notMember, message: nil),
            .server(status: 409, code: .roomFull, message: nil),
            .offline,
        ]
        for refusal in refusals {
            let store = SessionStore.inMemory()
            let api = FakeSessionAPI { $0.failures["joinSession"] = refusal }
            let engine = makeSquadEngine(clock: clock, api: api, store: store)
            await #expect(throws: refusal) {
                try await engine.joinSquadSession(sessionId: SquadData.sessionId, squadId: SquadData.squadId, minutes: 25)
            }
            #expect(engine.phase == .idle)
            #expect(engine.mode == .solo)
            #expect(engine.stored.room == nil)
            #expect(store.load()?.room == nil)
            #expect(api.liveViews == 0)
        }
    }

    @Test func withoutAnAPINothingStarts() async {
        let engine = makeSquadEngine(clock: clock, api: nil)
        await #expect(throws: APIError.notConfigured) {
            try await engine.joinSquadSession(sessionId: SquadData.sessionId, squadId: SquadData.squadId, minutes: 25)
        }
        #expect(engine.phase == .idle)
    }

    // MARK: - The push-to-start spike

    @Test func theTokenGoesWithTheJoin() async throws {
        let api = FakeSessionAPI()
        let engine = makeSquadEngine(clock: clock, api: api)
        let token = PushToStart(token: "c3d4e5f6", env: .production)

        let pushed = try await join(engine, pushToStart: token)

        #expect(pushed)
        #expect(api.pushToStarts == [token])
        #expect(engine.phase != .idle)
        // Waiting for the activity iOS starts; the foreground starts one here if it never comes.
        #expect(engine.stored.room?.activityID == nil)
        #expect(engine.liveActivityProblem == .notInForeground)
        #expect(engine.stored.room?.sessionId == SquadData.sessionId)
    }

    @Test func aPushThatCouldNotGoStartsTheActivityHere() async throws {
        let api = FakeSessionAPI { $0.pushedToStart = false }
        let engine = makeSquadEngine(clock: clock, api: api)

        let pushed = try await join(engine, pushToStart: PushToStart(token: "c3d4e5f6", env: .sandbox))

        #expect(!pushed)
        // Started the usual way (no controller in these tests, so nothing to see but no wait).
        #expect(engine.liveActivityProblem == nil)
        #expect(engine.phase != .idle)
    }

    @Test func aClosedRoomTakesTheTokenToTheNewOne() async throws {
        let api = FakeSessionAPI {
            $0.failures["joinSession"] = .server(status: 410, code: .sessionEnded, message: nil)
        }
        let engine = makeSquadEngine(clock: clock, api: api)
        let token = PushToStart(token: "c3d4e5f6", env: .production)

        let pushed = try await join(engine, pushToStart: token)

        #expect(pushed)
        #expect(api.pushToStarts == [token, token])
    }
}
