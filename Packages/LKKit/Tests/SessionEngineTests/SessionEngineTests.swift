import Core
import Foundation
import LiveActivity
import Model
import Testing
@testable import SessionEngine

// Every engine here runs on an in-memory store with no Live Activity controller, so nothing
// touches the disk or ActivityKit, and the clock only moves when a test moves it.

@MainActor
@Suite struct SessionTimingTests {
    let clock = TestClock(referenceDate)

    @Test func startsIdleWithDefaults() {
        let engine = makeEngine(clock: clock)
        #expect(engine.phase == .idle)
        #expect(engine.stats == .zero)
        #expect(engine.avatar == .default)
        #expect(engine.liveActivityProblem == nil)
    }

    @Test func startRunsForTheChosenMinutes() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        #expect(engine.phase == .running(
            startedAt: referenceDate,
            endsAt: referenceDate.addingTimeInterval(25 * 60),
            plannedMinutes: 25
        ))
        #expect(engine.completionTask != nil)
    }

    @Test(arguments: zip([-5, 0, 1, 25, 240, 241, 10_000], [1, 1, 1, 25, 240, 240, 240]))
    func minutesAreHeldToOneToFourHours(asked: Int, planned: Int) {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: asked)
        #expect(engine.phase == .running(
            startedAt: referenceDate,
            endsAt: referenceDate.addingTimeInterval(TimeInterval(planned * 60)),
            plannedMinutes: planned
        ))
    }

    @Test func aSecondStartIsIgnoredWhileRunningOrPaused() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        let running = engine.phase
        clock.advance(minutes: 1)
        engine.start(minutes: 90)
        #expect(engine.phase == running)

        engine.pause()
        let paused = engine.phase
        engine.start(minutes: 90)
        #expect(engine.phase == paused)
    }

    @Test func pauseFreezesTheTimerAndResumeMovesTheEnd() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 10)
        engine.pause()
        #expect(engine.phase == .paused(
            startedAt: referenceDate,
            endsAt: referenceDate.addingTimeInterval(25 * 60),
            pausedAt: referenceDate.addingTimeInterval(10 * 60),
            plannedMinutes: 25
        ))
        #expect(engine.completionTask == nil)

        clock.advance(minutes: 5)
        engine.resume()
        #expect(engine.phase == .running(
            startedAt: referenceDate,
            endsAt: referenceDate.addingTimeInterval(30 * 60),
            plannedMinutes: 25
        ))
        #expect(engine.completionTask != nil)
    }

    @Test func pausingTwiceAddsBothPauses() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 5)
        engine.pause()
        clock.advance(minutes: 3)
        engine.resume()
        clock.advance(minutes: 5)
        engine.pause()
        clock.advance(minutes: 7)
        engine.resume()
        // 25 minutes of focus plus 10 of pauses.
        #expect(engine.phase == .running(
            startedAt: referenceDate,
            endsAt: referenceDate.addingTimeInterval(35 * 60),
            plannedMinutes: 25
        ))
    }

    @Test func pauseAndResumeOnlyApplyInTheirPhase() {
        let engine = makeEngine(clock: clock)
        engine.resume()
        engine.pause()
        #expect(engine.phase == .idle)

        engine.start(minutes: 25)
        let running = engine.phase
        engine.resume()
        #expect(engine.phase == running)
    }

    @Test func reconcileFinishesWhenTheTimeRunsOut() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(seconds: 25 * 60 - 1)
        engine.reconcile()
        #expect(engine.phase.record == nil)

        clock.advance(seconds: 1)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        #expect(record.plannedMinutes == 25)
        #expect(record.focusedSeconds == 25 * 60)
        #expect(record.coinsEarned == 25 + SessionRecord.completionBonus)
        #expect(record.startedAt == referenceDate)
        #expect(record.endedAt == referenceDate.addingTimeInterval(25 * 60))
        #expect(engine.stats.coins == 30)
        #expect(engine.stats.completedSessions == 1)
        #expect(engine.completionTask == nil)
        #expect(engine.activeSession == nil)
    }

    @Test func aSessionNoticedLateEndsWhenItsTimeRanOut() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 50)
        clock.advance(minutes: 3 * 60)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        #expect(record.endedAt == referenceDate.addingTimeInterval(50 * 60))
        #expect(record.coinsEarned == 55)
    }

    @Test func completionCountsPauses() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 10)
        engine.pause()
        clock.advance(minutes: 5)
        engine.resume()
        clock.advance(minutes: 14)
        engine.reconcile()
        #expect(engine.phase.record == nil)

        clock.advance(minutes: 1)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        #expect(record.focusedSeconds == 25 * 60)
        #expect(record.endedAt == referenceDate.addingTimeInterval(30 * 60))
    }

    @Test func aPausedSessionNeverCompletesOnItsOwn() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 10)
        engine.pause()
        clock.advance(minutes: 60)
        engine.reconcile()
        guard case .paused = engine.phase else {
            Issue.record("Expected paused, got \(engine.phase)")
            return
        }
    }

    @Test func aSessionPausedForEightHoursIsEndedEarly() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 10)
        engine.pause()
        clock.advance(minutes: 8 * 60)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 10 * 60)
    }

    @Test func endingEarlyPaysTheFocusedMinutesOnly() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 50)
        clock.advance(minutes: 12.5)
        engine.end()
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 750)
        #expect(record.coinsEarned == 12)
        #expect(record.endedAt == referenceDate.addingTimeInterval(750))
        #expect(engine.stats.coins == 12)
        #expect(engine.stats.completedSessions == 0)
    }

    @Test func endingWhilePausedCountsUpToThePause() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 10)
        engine.pause()
        clock.advance(minutes: 30)
        engine.end()
        let record = try #require(engine.phase.record)
        #expect(!record.completed)
        #expect(record.focusedSeconds == 600)
        #expect(record.coinsEarned == 10)
    }

    @Test func endingStraightAwayEarnsNothing() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        engine.end()
        let record = try #require(engine.phase.record)
        #expect(record.focusedSeconds == 0)
        #expect(record.coinsEarned == 0)
    }

    @Test func aSoloSlipLeavesTheTimerRunning() {
        // Decision 0009: a slip never ends the timer, and solo there's no squad to show it to.
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 10)
        engine.slip()
        #expect(engine.phase == .running(
            startedAt: referenceDate,
            endsAt: referenceDate.addingTimeInterval(25 * 60),
            plannedMinutes: 25
        ))
    }

    @Test func endingOrPausingAfterTheTimeRanOutCompletes() throws {
        let ended = makeEngine(clock: clock)
        ended.start(minutes: 25)
        let paused = makeEngine(clock: clock)
        paused.start(minutes: 25)
        clock.advance(minutes: 26)

        ended.end()
        paused.pause()
        let endedRecord = try #require(ended.phase.record)
        let pausedRecord = try #require(paused.phase.record)
        #expect(endedRecord.completed)
        #expect(pausedRecord.completed)
    }

    @Test func dismissingTheFinishReturnsToIdleAndANewSessionCanStart() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        engine.end()
        engine.start(minutes: 50)
        guard case .running(_, _, 50) = engine.phase else {
            Issue.record("A new session should start from the finish screen")
            return
        }
        engine.end()
        engine.dismissFinished()
        #expect(engine.phase == .idle)
        engine.dismissFinished()
        #expect(engine.phase == .idle)
    }

    @Test func liveActivityCommandsDriveTheSession() async throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 5)
        await engine.handle(.pause)
        guard case .paused = engine.phase else {
            Issue.record("Pause should pause")
            return
        }
        await engine.handle(.resume)
        guard case .running = engine.phase else {
            Issue.record("Resume should resume")
            return
        }
        await engine.handle(.end)
        let record = try #require(engine.phase.record)
        #expect(record.focusedSeconds == 5 * 60)
    }

    /// The "Lock in" widget and control (M6).
    @Test func startCommandStartsASoloSession() async throws {
        let engine = makeEngine(clock: clock)
        await engine.handle(.start(minutes: 25))
        guard case .running(let startedAt, let endsAt, 25) = engine.phase else {
            Issue.record("Start should start a 25-minute session")
            return
        }
        #expect(startedAt == clock.now)
        #expect(endsAt == clock.now.addingTimeInterval(25 * 60))
        #expect(engine.mode == .solo)
    }

    /// A widget tapped mid-session leaves that session alone, running or paused.
    @Test func startCommandDoesNothingWhileASessionIsGoing() async throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 50)
        let running = engine.phase
        clock.advance(minutes: 5)
        await engine.handle(.start(minutes: 25))
        #expect(engine.phase == running)

        await engine.handle(.pause)
        let paused = engine.phase
        clock.advance(minutes: 5)
        await engine.handle(.start(minutes: 25))
        #expect(engine.phase == paused)
    }

    /// From the finish screen it's a new session; once the old one has run out, too.
    @Test func startCommandAfterAFinishStartsANewSession() async throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 30)
        await engine.handle(.start(minutes: 25))
        guard case .running(let startedAt, _, 25) = engine.phase else {
            Issue.record("Start after the time ran out should start a new session")
            return
        }
        #expect(startedAt == clock.now)
        #expect(engine.stats.completedSessions == 1)
    }

    @Test func aCommandAfterTheTimeRanOutFinishesTheSession() async throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        clock.advance(minutes: 30)
        await engine.handle(.pause)
        let record = try #require(engine.phase.record)
        #expect(record.completed)
    }
}

@MainActor
@Suite struct LiveActivityStateTests {
    let clock = TestClock(referenceDate)

    @Test func soloStateFollowsTheSession() throws {
        let engine = makeEngine(clock: clock)
        engine.avatar = AvatarCode("b3.c7.e2.h4")
        engine.start(minutes: 25)
        var session = try #require(engine.activeSession)
        var state = engine.contentState(for: session)
        let attributes = LockinAttributes.solo(me: engine.memberID, sid: session.id)
        #expect(state.v == 1)
        #expect(state.m.count == 1)
        #expect(state.p == nil && state.c == nil)
        var member = try #require(state.m.first)
        #expect(member.i == engine.memberID)
        #expect(member.n == "You")
        #expect(member.a == "b3.c7.e2.h4")
        #expect(member.state == .focusing)
        #expect(member.b == referenceDate.timeIntervalSince1970)
        #expect(member.e == referenceDate.timeIntervalSince1970 + 25 * 60)
        #expect(member.q == nil)
        #expect(attributes.fitsPayloadBudget(state))

        clock.advance(minutes: 10)
        engine.pause()
        session = try #require(engine.activeSession)
        state = engine.contentState(for: session)
        member = try #require(state.m.first)
        #expect(state.v == 2)
        #expect(member.state == .paused)
        #expect(member.q == referenceDate.timeIntervalSince1970 + 10 * 60)
        #expect(member.remaining(at: clock.now.addingTimeInterval(3_600)) == 15 * 60)

        clock.advance(minutes: 5)
        engine.resume()
        session = try #require(engine.activeSession)
        state = engine.contentState(for: session)
        member = try #require(state.m.first)
        #expect(state.v == 3)
        #expect(member.state == .focusing)
        #expect(member.q == nil)
        // The start moves with the pause, so the bar shows 10 of 25 minutes done.
        #expect(member.b == referenceDate.timeIntervalSince1970 + 5 * 60)
        #expect(member.e == referenceDate.timeIntervalSince1970 + 30 * 60)

        let done = engine.contentState(for: session, showing: .done)
        #expect(done.m.first?.state == .done)
        #expect(done.m.first?.q == nil)
    }

    @Test func changingTheAvatarMidSessionRaisesTheVersion() throws {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        engine.avatar = AvatarCode(body: 1)
        let session = try #require(engine.activeSession)
        #expect(session.version == 2)
        #expect(engine.contentState(for: session).m.first?.a == "b1.c0.e0.h0")
    }

    @Test func withoutAControllerThereIsNoProblemToReport() {
        let engine = makeEngine(clock: clock)
        engine.start(minutes: 25)
        #expect(engine.liveActivityProblem == nil)
        #expect(engine.activeSession?.activityID == nil)
    }
}

@MainActor
@Suite struct PersistenceTests {
    let clock = TestClock(referenceDate)

    @Test func aPausedSessionSurvivesARelaunch() {
        let store = SessionStore.inMemory()
        let first = makeEngine(clock: clock, store: store)
        first.avatar = AvatarCode("b2.c5.e1.h3")
        first.start(minutes: 50)
        clock.advance(minutes: 20)
        first.pause()

        let second = makeEngine(clock: clock, store: store)
        #expect(second.phase == first.phase)
        #expect(second.avatar == AvatarCode("b2.c5.e1.h3"))
        #expect(second.memberID == first.memberID)
        #expect(second.activeSession == first.activeSession)
    }

    @Test func aRunningSessionThatEndedWhileClosedFinishesAtLaunch() throws {
        let store = SessionStore.inMemory()
        let first = makeEngine(clock: clock, store: store)
        first.start(minutes: 25)
        clock.advance(minutes: 40)

        let second = makeEngine(clock: clock, store: store)
        let record = try #require(second.phase.record)
        #expect(record.completed)
        #expect(second.stats.coins == 30)

        // Finished means saved: a third launch doesn't pay twice.
        let third = makeEngine(clock: clock, store: store)
        #expect(third.phase == .idle)
        #expect(third.stats.coins == 30)
        #expect(third.stats.completedSessions == 1)
    }

    @Test func memberIDIsMadeOnceAndKept() {
        let store = SessionStore.inMemory()
        let first = makeEngine(clock: clock, store: store)
        #expect(first.memberID.count == 10)
        #expect(ShortID.isValid(first.memberID))
        let second = makeEngine(clock: clock, store: store)
        #expect(second.memberID == first.memberID)
        #expect(store.load()?.memberID == first.memberID)
    }

    @Test func anInvalidMemberIDIsReplaced() {
        let store = SessionStore.inMemory()
        store.save(StoredSessions(memberID: "not an id"))
        let engine = makeEngine(clock: clock, store: store)
        #expect(ShortID.isValid(engine.memberID))
        #expect(store.load()?.memberID == engine.memberID)
    }

    @Test func historyAndCoinsAccumulateAcrossLaunches() {
        let store = SessionStore.inMemory()
        for minutes in [25, 50] {
            let engine = makeEngine(clock: clock, store: store)
            engine.start(minutes: minutes)
            clock.advance(minutes: Double(minutes))
            engine.reconcile()
            clock.advance(minutes: 1)
        }
        let engine = makeEngine(clock: clock, store: store)
        #expect(engine.stats.coins == 30 + 55)
        #expect(engine.stats.completedSessions == 2)
        #expect(store.load()?.history.map(\.plannedMinutes) == [25, 50])
    }

    @Test func theAvatarIsSavedWhenSet() {
        let store = SessionStore.inMemory()
        let first = makeEngine(clock: clock, store: store)
        first.avatar = AvatarCode(body: 4, colour: 2, eyes: 1, hat: 0)
        #expect(store.load()?.avatar == "b4.c2.e1.h0")
        #expect(makeEngine(clock: clock, store: store).avatar == AvatarCode(body: 4, colour: 2, eyes: 1, hat: 0))
    }
}

@MainActor
@Suite struct EngineStatsTests {
    @Test func todaysMinutesRollOverAtMidnight() throws {
        // 23:50 in Sydney: the session finishes after midnight.
        let clock = TestClock(date(2027, 3, 10, 23, 50))
        let engine = makeEngine(clock: clock)
        engine.calendar = sydney
        engine.reconcile()

        engine.start(minutes: 25)
        clock.advance(minutes: 25)
        engine.reconcile()
        let record = try #require(engine.phase.record)
        #expect(record.completed)
        // Finished at 00:15: it counts for the new day.
        #expect(engine.stats.todayMinutes == 25)
        #expect(engine.stats.streakDays == 1)

        clock.now = date(2027, 3, 12, 0, 1)
        engine.reconcile()
        #expect(engine.stats.todayMinutes == 0)
        // Yesterday counted, and today isn't over yet.
        #expect(engine.stats.streakDays == 1)

        clock.now = date(2027, 3, 13, 0, 1)
        engine.reconcile()
        #expect(engine.stats.streakDays == 0)
    }

    @Test func firstCompletionIsCountedOnce() {
        let clock = TestClock(referenceDate)
        let recorder = EventRecorder()
        let engine = makeEngine(clock: clock)
        engine.analytics = Analytics { name, _ in recorder.record(name) }

        engine.start(minutes: 25)
        engine.end()
        #expect(recorder.names.isEmpty)

        for _ in 0..<2 {
            engine.start(minutes: 25)
            clock.advance(minutes: 25)
            engine.reconcile()
        }
        #expect(recorder.names == [
            AnalyticsEvent.sessionCompleted.rawValue,
            AnalyticsEvent.firstSessionCompleted.rawValue,
            AnalyticsEvent.sessionCompleted.rawValue,
        ])
    }
}

@MainActor
@Suite struct PreviewTests {
    @Test func showsWhatItWasGivenAndHasNoSideEffects() {
        let start = Date(timeIntervalSince1970: 1_000)
        let phase = SessionEngine.Phase.running(
            startedAt: start,
            endsAt: start.addingTimeInterval(25 * 60),
            plannedMinutes: 25
        )
        let stats = FocusStats(todayMinutes: 50, streakDays: 3, coins: 120, completedSessions: 4)
        let avatar = AvatarCode("b1.c2.e3.h4")
        let engine = SessionEngine.preview(phase: phase, stats: stats, avatar: avatar)

        #expect(engine.isPreview)
        #expect(engine.phase == phase)
        #expect(engine.stats == stats)
        #expect(engine.avatar == avatar)
        #expect(engine.liveActivities == nil)
        #expect(engine.completionTask == nil)

        // Long past its end, and still running: a preview never reconciles.
        engine.reconcile()
        #expect(engine.phase == phase)

        engine.avatar = AvatarCode(body: 2)
        engine.pause()
        engine.resume()
        engine.end()
        engine.dismissFinished()
        engine.start(minutes: 50)
        #expect(engine.completionTask == nil)
        #expect(engine.store.load() == nil)
    }

    @Test func canShowALiveActivityProblem() {
        let engine = SessionEngine.preview(
            phase: .idle,
            stats: .zero,
            avatar: .default,
            liveActivityProblem: .disabled
        )
        #expect(engine.liveActivityProblem == .disabled)
    }
}
