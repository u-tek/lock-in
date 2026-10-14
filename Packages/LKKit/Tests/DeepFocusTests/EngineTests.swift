import Foundation
import Testing
@testable import DeepFocus

// The engine on fakes: what it records in the App Group, what it asks ManagedSettings to shield,
// and which DeviceActivity schedules it starts and stops. No system calls.

@Suite struct SessionShieldingTests {
    private let now = referenceDate
    private var end: Date { now.addingTimeInterval(minutes(25)) }

    @Test func startShieldsAndSchedulesTheSession() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let outcome = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: true, now: now)
        #expect(outcome == .shielding)
        #expect(fixture.shields.last == .shield(except: []))
        #expect(fixture.monitor.starts(of: .session) == [DeepFocusSchedule(start: now, end: end)])
        #expect(fixture.state.session == DeepFocusState.Session(
            id: "s1", endsAt: end.timeIntervalSince1970, isPaused: false, withSquad: true
        ))
        #expect(fixture.state.isShielding(at: now))
    }

    @Test func aShortSessionGetsAStretchedSchedule() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let soon = now.addingTimeInterval(minutes(10))
        #expect(fixture.engine.start(sessionID: "s1", endsAt: soon, withSquad: false, now: now) == .shielding)
        let schedule = try #require(fixture.monitor.starts(of: .session).first)
        #expect(schedule.end == soon)
        #expect(schedule.duration >= DeepFocusSchedule.minimumInterval)
    }

    @Test func aRefusedScheduleStillShields() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        fixture.monitor.refusesToStart = true
        let outcome = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        #expect(outcome == .shieldingWhileLockinRuns)
        #expect(fixture.shields.last == .shield(except: []))
    }

    @Test func nothingChosenShieldsNothingButRemembersTheSession() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        fixture.shields.hasSelection = false
        #expect(fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now) == .nothingSelected)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.state.session?.id == "s1")
        // Choosing apps mid-session shields them on the next sync.
        fixture.shields.hasSelection = true
        fixture.engine.sync(now: now.addingTimeInterval(minutes(1)))
        #expect(fixture.shields.last == .shield(except: []))
    }

    @Test func aSessionThatsAlreadyOverDoesNothing() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let outcome = fixture.engine.start(sessionID: "s1", endsAt: now.addingTimeInterval(30), withSquad: false, now: now)
        #expect(outcome == .ended)
        #expect(fixture.state.session == nil)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.monitor.starts(of: .session).isEmpty)
    }

    @Test func aNewSessionReplacesTheOld() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        _ = fixture.engine.start(sessionID: "s2", endsAt: end.addingTimeInterval(minutes(5)), withSquad: true, now: now)
        #expect(fixture.state.session?.id == "s2")
        #expect(fixture.monitor.starts(of: .session).count == 2)
    }

    @Test func pauseLiftsAndResumeShieldsAgain() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)

        let pausedAt = now.addingTimeInterval(minutes(5))
        fixture.engine.pause(now: pausedAt)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.monitor.stops(of: .session) == 1)
        #expect(fixture.state.session?.isPaused == true)
        #expect(!fixture.state.isShielding(at: pausedAt))

        // Paused for 5 minutes: the end moves 5 minutes later.
        let resumedAt = now.addingTimeInterval(minutes(10))
        let newEnd = end.addingTimeInterval(minutes(5))
        #expect(fixture.engine.resume(endsAt: newEnd, now: resumedAt) == .shielding)
        #expect(fixture.shields.last == .shield(except: []))
        #expect(fixture.monitor.starts(of: .session).last == DeepFocusSchedule(start: resumedAt, end: newEnd))
        #expect(fixture.state.session == DeepFocusState.Session(
            id: "s1", endsAt: newEnd.timeIntervalSince1970, isPaused: false, withSquad: false
        ))
    }

    @Test func aSyncWhilePausedKeepsTheShieldsDown() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        fixture.engine.pause(now: now.addingTimeInterval(60))
        // The monitor extension's intervalDidEnd after the pause stopped the schedule.
        fixture.engine.sync(now: now.addingTimeInterval(61))
        #expect(fixture.shields.last == .clear)
    }

    @Test func resumingWithNoSessionIsEnded() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        #expect(fixture.engine.resume(endsAt: end, now: now) == .ended)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.state.session == nil)
    }

    @Test func stopLiftsEverythingAndForgets() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: now.addingTimeInterval(60))
        fixture.engine.stop(now: now.addingTimeInterval(120))
        #expect(fixture.shields.last == .clear)
        #expect(fixture.state.session == nil)
        #expect(fixture.state.graces.isEmpty)
        #expect(fixture.state.graceTimerEnd == nil)
        #expect(fixture.monitor.stops(of: .session) >= 1)
        #expect(fixture.monitor.stops(of: .grace) >= 1)
    }

    @Test func neverStopsEveryActivityByAccident() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: now)
        fixture.engine.sync(now: now.addingTimeInterval(minutes(6)))
        fixture.engine.pause(now: now.addingTimeInterval(minutes(7)))
        _ = fixture.engine.resume(endsAt: end.addingTimeInterval(minutes(1)), now: now.addingTimeInterval(minutes(8)))
        fixture.engine.stop(now: now.addingTimeInterval(minutes(9)))
        fixture.engine.stop(now: now.addingTimeInterval(minutes(10)))
        // DeviceActivityCenter.stopMonitoring([]) would stop every activity.
        #expect(!fixture.monitor.stopped.isEmpty)
        #expect(fixture.monitor.stopped.allSatisfy { !$0.isEmpty })
    }

    @Test func theSessionsEndLiftsTheShields() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        fixture.engine.sync(now: end)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.state.session?.id == "s1", "the app forgets it with stop()")
    }

    /// intervalDidEnd a moment early must still end it: putting the shields back up then would
    /// leave nothing to take them down.
    @Test func anEndCallbackALittleEarlyStillEnds() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        fixture.engine.sync(now: end.addingTimeInterval(-30))
        #expect(fixture.shields.last == .clear)
    }

    @Test func aStartCallbackMidSessionChangesNothing() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: false, now: now)
        let before = fixture.state
        fixture.engine.sync(now: now.addingTimeInterval(1))
        #expect(fixture.shields.last == .shield(except: []))
        #expect(fixture.state == before)
    }

    @Test func noRecordedStateLiftsEverything() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        fixture.engine.sync(now: now)
        #expect(fixture.shields.calls == [.clear])
        #expect(fixture.monitor.started.isEmpty)
    }
}

@Suite struct ShieldButtonTests {
    private let now = referenceDate
    private var end: Date { now.addingTimeInterval(minutes(25)) }

    private func running(withSquad: Bool = true) throws -> EngineFixture {
        let fixture = try EngineFixture()
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: withSquad, now: now)
        return fixture
    }

    @Test func backToFocusClosesTheApp() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        let calls = fixture.shields.calls.count
        #expect(fixture.engine.handleShieldAction(.primary, target: .application, token: token("app1"), now: now) == .closeApp)
        #expect(fixture.engine.slips.pending().isEmpty)
        #expect(fixture.shields.calls.count == calls)
    }

    @Test func openAnywayRecordsASlipAndLetsTheAppThrough() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        let tappedAt = now.addingTimeInterval(minutes(3))
        let response = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: tappedAt)
        #expect(response == .redrawShield)

        let slips = fixture.engine.slips.pending()
        #expect(slips.count == 1)
        #expect(slips.first?.sessionID == "s1")
        #expect(slips.first?.at == tappedAt.timeIntervalSince1970)
        #expect(slips.first?.appName == nil)

        #expect(fixture.shields.last == .shield(except: [token("app1")]))
        let graceEnd = tappedAt.addingTimeInterval(DeepFocusEngine.graceLength)
        #expect(fixture.state.graces == [DeepFocusState.Grace(
            target: .application, token: token("app1"), until: graceEnd.timeIntervalSince1970
        )])
        let graceSchedule = try #require(DeepFocusSchedule.ending(at: graceEnd, now: tappedAt))
        #expect(fixture.monitor.starts(of: .grace) == [graceSchedule])
        #expect(fixture.state.graceTimerEnd == graceEnd.timeIntervalSince1970)
    }

    @Test func theAppIsShieldedAgainWhenTheGraceRunsOut() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: now)
        // The grace timer's intervalDidEnd, in the monitor extension.
        fixture.engine.sync(now: now.addingTimeInterval(DeepFocusEngine.graceLength))
        #expect(fixture.shields.last == .shield(except: []))
        #expect(fixture.state.graces.isEmpty)
        #expect(fixture.state.graceTimerEnd == nil)
        #expect(fixture.monitor.stops(of: .grace) == 1)
    }

    /// Starting the grace timer calls intervalDidStart straight away (its interval reaches back
    /// into the past), and replacing it may call intervalDidEnd: neither may start it again.
    @Test func syncingAgainLeavesTheGraceTimerAlone() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: now)
        for second in [1.0, 60, 120, 200] {
            fixture.engine.sync(now: now.addingTimeInterval(second))
        }
        #expect(fixture.monitor.starts(of: .grace).count == 1)
        #expect(fixture.monitor.stops(of: .grace) == 0)
        #expect(fixture.shields.last == .shield(except: [token("app1")]))
    }

    @Test func theGraceTimerFollowsTheFirstGraceToRunOut() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        let first = now.addingTimeInterval(minutes(3))
        let second = now.addingTimeInterval(minutes(5))
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: first)
        _ = fixture.engine.handleShieldAction(.secondary, target: .webDomain, token: token("site1"), now: second)
        #expect(fixture.shields.last == .shield(except: [token("app1"), token("site1")]))
        #expect(fixture.monitor.starts(of: .grace).count == 1, "the first grace still ends first")
        #expect(fixture.engine.slips.pending().count == 2)

        let firstEnds = first.addingTimeInterval(DeepFocusEngine.graceLength)
        fixture.engine.sync(now: firstEnds)
        #expect(fixture.shields.last == .shield(except: [token("site1")]))
        let secondEnds = second.addingTimeInterval(DeepFocusEngine.graceLength)
        #expect(fixture.monitor.starts(of: .grace).last == DeepFocusSchedule.ending(at: secondEnds, now: firstEnds))

        fixture.engine.sync(now: secondEnds)
        #expect(fixture.shields.last == .shield(except: []))
        #expect(fixture.monitor.stops(of: .grace) == 1)
    }

    @Test func openAnywayAgainOnTheSameAppKeepsOneGrace() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: now)
        let later = now.addingTimeInterval(minutes(6))
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: later)
        #expect(fixture.state.graces.count == 1)
        #expect(fixture.state.graces.first?.until == later.addingTimeInterval(DeepFocusEngine.graceLength).timeIntervalSince1970)
        #expect(fixture.engine.slips.pending().count == 2)
    }

    @Test func aCategoryIsLetThroughByItsOwnToken() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        _ = fixture.engine.handleShieldAction(.secondary, target: .category, token: token("social"), now: now)
        #expect(fixture.state.graces.map(\.target) == [.category])
        #expect(fixture.shields.last == .shield(except: [token("social")]))
    }

    @Test func withoutATokenTheSlipStillCounts() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        #expect(fixture.engine.handleShieldAction(.secondary, target: .application, token: nil, now: now) == .keepShield)
        #expect(fixture.engine.slips.pending().count == 1)
        #expect(fixture.state.graces.isEmpty)
    }

    @Test func aShieldLeftUpAfterTheSessionUnlocks() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        let after = end.addingTimeInterval(minutes(1))
        #expect(fixture.engine.handleShieldAction(.primary, target: .application, token: token("app1"), now: after) == .redrawShield)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: after) == .redrawShield)
        #expect(fixture.engine.slips.pending().isEmpty, "no session, no slip")
    }

    @Test func theSessionsEndEndsEveryGrace() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        let late = end.addingTimeInterval(-minutes(2))
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: late)
        fixture.engine.sync(now: end)
        #expect(fixture.shields.last == .clear)
        #expect(fixture.state.graces.isEmpty)
        #expect(fixture.monitor.stops(of: .grace) == 1)
    }

    @Test func aRefusedGraceTimerIsTriedAgain() throws {
        let fixture = try running()
        defer { fixture.tearDown() }
        fixture.monitor.refusesToStart = true
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: now)
        #expect(fixture.state.graceTimerEnd == nil)
        #expect(fixture.shields.last == .shield(except: [token("app1")]))
        fixture.monitor.refusesToStart = false
        fixture.engine.sync(now: now.addingTimeInterval(10))
        #expect(fixture.monitor.starts(of: .grace).count == 1)
        #expect(fixture.state.graceTimerEnd != nil)
    }

    @Test func theShieldSaysWhatsGoingOn() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        #expect(fixture.engine.shieldContent(appName: "Instagram", now: now) == .lifted(appName: "Instagram"))
        _ = fixture.engine.start(sessionID: "s1", endsAt: end, withSquad: true, now: now)
        #expect(fixture.engine.shieldContent(appName: "Instagram", now: now) == .locked(appName: "Instagram", withSquad: true))
        fixture.engine.pause(now: now.addingTimeInterval(60))
        #expect(fixture.engine.shieldContent(appName: nil, now: now.addingTimeInterval(61)) == .lifted(appName: nil))
        _ = fixture.engine.start(sessionID: "s2", endsAt: end, withSquad: false, now: now)
        #expect(fixture.engine.shieldContent(appName: "X", now: now) == .locked(appName: "X", withSquad: false))
        #expect(fixture.engine.shieldContent(appName: "X", now: end) == .lifted(appName: "X"))
    }
}

@Suite struct StateFileTests {
    @Test func roundTripsThroughJSON() throws {
        let state = DeepFocusState(
            session: .init(id: "s1", endsAt: 1_800_001_500.5, isPaused: true, withSquad: true),
            graces: [.init(target: .webDomain, token: token("site"), until: 1_800_000_300)],
            graceTimerEnd: 1_800_000_300
        )
        let decoded = try JSONDecoder().decode(DeepFocusState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    @Test func missingPartsDecodeAsNothing() throws {
        let json = #"{"session":{"id":"s1","endsAt":1800001500,"isPaused":false,"withSquad":false},"later":1}"#
        let state = try JSONDecoder().decode(DeepFocusState.self, from: Data(json.utf8))
        #expect(state.session?.id == "s1")
        #expect(state.graces.isEmpty)
        #expect(state.graceTimerEnd == nil)
        #expect(try JSONDecoder().decode(DeepFocusState.self, from: Data("{}".utf8)) == DeepFocusState())
    }

    @Test func anUnreadableStateFileMeansNoSession() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        try Data("{".utf8).write(to: fixture.storage.stateURL)
        #expect(fixture.state == DeepFocusState())
        fixture.engine.sync(now: referenceDate)
        #expect(fixture.shields.last == .clear)
    }
}

@Suite @MainActor struct ControllerTests {
    private final class Clock {
        var now = referenceDate
    }

    @Test func publishesTheSessionAsItGoes() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let clock = Clock()
        let controller = DeepFocusController(engine: fixture.engine, now: { clock.now })
        #expect(controller.sessionID == nil)
        #expect(!controller.isShielding)

        let end = clock.now.addingTimeInterval(minutes(25))
        #expect(controller.start(sessionEnds: end, sessionID: "s1", withSquad: true) == .shielding)
        #expect(controller.sessionID == "s1")
        #expect(controller.isShielding)

        clock.now = clock.now.addingTimeInterval(minutes(5))
        controller.pause()
        #expect(controller.sessionID == "s1")
        #expect(!controller.isShielding)

        clock.now = clock.now.addingTimeInterval(minutes(2))
        #expect(controller.resume(sessionEnds: end.addingTimeInterval(minutes(2))) == .shielding)
        #expect(controller.isShielding)

        controller.stop()
        #expect(controller.sessionID == nil)
        #expect(!controller.isShielding)
        #expect(fixture.shields.last == .clear)
    }

    @Test func reconcileAfterTheEndLiftsTheShields() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let clock = Clock()
        let controller = DeepFocusController(engine: fixture.engine, now: { clock.now })
        controller.start(sessionEnds: clock.now.addingTimeInterval(minutes(25)), sessionID: "s1")
        clock.now = clock.now.addingTimeInterval(minutes(26))
        controller.reconcile()
        #expect(!controller.isShielding)
        #expect(fixture.shields.last == .clear)
    }

    @Test func aNewControllerPicksUpWhatWasRecorded() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let clock = Clock()
        DeepFocusController(engine: fixture.engine, now: { clock.now })
            .start(sessionEnds: clock.now.addingTimeInterval(minutes(25)), sessionID: "s1")
        let relaunched = DeepFocusController(engine: fixture.engine, now: { clock.now })
        #expect(relaunched.sessionID == "s1")
        #expect(relaunched.isShielding)
    }

    @Test func drainsTheSlipsTheShieldRecorded() throws {
        let fixture = try EngineFixture()
        defer { fixture.tearDown() }
        let clock = Clock()
        let controller = DeepFocusController(engine: fixture.engine, now: { clock.now })
        controller.start(sessionEnds: clock.now.addingTimeInterval(minutes(25)), sessionID: "s1")
        _ = fixture.engine.handleShieldAction(.secondary, target: .application, token: token("app1"), now: clock.now)
        let slips = controller.drainSlips()
        #expect(slips.map(\.sessionID) == ["s1"])
        #expect(controller.drainSlips().isEmpty)
    }

    @Test func thePreviewTouchesNothingReal() {
        let controller = DeepFocusController.preview()
        #expect(controller.start(sessionEnds: Date().addingTimeInterval(minutes(25)), sessionID: "preview") == .shielding)
        #expect(controller.isShielding)
        controller.stop()
        #expect(controller.sessionID == nil)
    }
}
