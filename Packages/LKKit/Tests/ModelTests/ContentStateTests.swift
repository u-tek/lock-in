import Foundation
import Testing
@testable import Model

private typealias State = LockinAttributes.ContentState
private typealias Member = LockinAttributes.ContentState.Member

/// Ten minutes into the squad-6 fixture's session.
private let now = Date(timeIntervalSince1970: 1_791_900_600)

private func member(_ id: String, _ state: MemberState, end: Double, pausedAt: Double? = nil) -> Member {
    Member(i: id, n: id, a: "b0.c0.e0.h0", s: state.rawValue, b: now.timeIntervalSince1970 - 600, e: end, q: pausedAt)
}

@Suite struct MemberTests {
    @Test func remainingCountsDownWhileRunning() {
        let running = member("ava", .focusing, end: now.timeIntervalSince1970 + 900)
        #expect(running.remaining(at: now) == 900)
        #expect(running.remaining(at: now.addingTimeInterval(899)) == 1)
        #expect(running.remaining(at: now.addingTimeInterval(900)) == 0)
        // Never negative.
        #expect(running.remaining(at: now.addingTimeInterval(5_000)) == 0)
        #expect(member("noor", .onBreak, end: now.timeIntervalSince1970 + 60).remaining(at: now) == 60)
    }

    @Test func remainingIsFrozenWhilePaused() {
        // Kai in squad-6: paused with 780 seconds to go.
        let paused = Member(i: "Ka9Lm3Vx0c", n: "Kai", a: "b2.c4.e1.h2", s: 2, b: 1_791_899_880, e: 1_791_901_380, q: 1_791_900_600)
        #expect(paused.remaining(at: now) == 780)
        #expect(paused.remaining(at: now.addingTimeInterval(10_000)) == 780)
        #expect(paused.remaining(at: .distantPast) == 780)
        #expect(paused.pausedDate == Date(timeIntervalSince1970: 1_791_900_600))
    }

    @Test func remainingWhilePausedIsNeverNegative() {
        let pausedLate = member("kai", .paused, end: 100, pausedAt: 200)
        #expect(pausedLate.remaining(at: now) == 0)
    }

    @Test func pausedWithoutAPausedAtTimeCountsFromNow() {
        let paused = member("kai", .paused, end: now.timeIntervalSince1970 + 300)
        #expect(paused.remaining(at: now) == 300)
    }

    @Test func aPausedAtTimeOnlyFreezesAPausedMember() {
        // A stale q on a running member is ignored.
        let running = member("ava", .focusing, end: now.timeIntervalSince1970 + 900, pausedAt: now.timeIntervalSince1970 - 100)
        #expect(running.remaining(at: now) == 900)
    }

    @Test func datesMatchTheUnixSeconds() {
        let ava = member("ava", .focusing, end: 1_791_901_500)
        #expect(ava.startDate == Date(timeIntervalSince1970: 1_791_900_000))
        #expect(ava.endDate == Date(timeIntervalSince1970: 1_791_901_500))
        #expect(ava.pausedDate == nil)
        #expect(ava.timerRange == ava.startDate...ava.endDate)
    }

    @Test func timerRangeIsNeverInverted() {
        let backwards = Member(i: "x", n: "x", a: "", s: 0, b: 2_000, e: 1_000)
        #expect(backwards.timerRange.lowerBound == Date(timeIntervalSince1970: 2_000))
        #expect(backwards.timerRange.upperBound == Date(timeIntervalSince1970: 2_000))

        let broken = Member(i: "x", n: "x", a: "", s: 0, b: .nan, e: -.infinity)
        #expect(broken.timerRange.lowerBound <= broken.timerRange.upperBound)
    }

    @Test(arguments: [-1, 6, 42, Int.max, Int.min])
    func unknownStatesReadAsFocusing(raw: Int) {
        let future = Member(i: "x", n: "x", a: "", s: raw, b: 0, e: 1)
        #expect(future.state == .focusing)
        #expect(future.isActive)
    }

    @Test func stateNumbersMatchTheSpec() {
        #expect(MemberState.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(MemberState.allCases.filter(\.isActive) == [.focusing, .onBreak, .paused])
    }

    @Test func settingTheStateWritesTheNumber() {
        var ava = member("ava", .focusing, end: 0)
        ava.state = .done
        #expect(ava.s == 3)
        #expect(ava.state == .done)
        #expect(!ava.isActive)
    }

    @Test func readableInitialiserMatchesTheWireOne() {
        let readable = Member(
            id: "Ka9Lm3Vx0c",
            name: "Kai",
            avatar: AvatarCode(body: 2, colour: 4, eyes: 1, hat: 2),
            state: .paused,
            start: Date(timeIntervalSince1970: 1_791_899_880),
            end: Date(timeIntervalSince1970: 1_791_901_380),
            pausedAt: Date(timeIntervalSince1970: 1_791_900_600)
        )
        let wire = Member(i: "Ka9Lm3Vx0c", n: "Kai", a: "b2.c4.e1.h2", s: 2, b: 1_791_899_880, e: 1_791_901_380, q: 1_791_900_600)
        #expect(readable == wire)
        #expect(readable.avatar == AvatarCode("b2.c4.e1.h2"))
    }
}

@Suite struct ContentStateTests {
    @Test func staleFiveMinutesAfterTheLastRunningTimer() throws {
        // Ava ends at …1500, Noor (on a break) at …2700, Kai is paused with 780 s left (…1380 if
        // resumed now). Mateo is done, Sakura left and Jules slipped: they don't count, even
        // though Jules's end (…3060) is the latest.
        let state = try Fixture.contentState("squad-6")
        #expect(state.staleDate(now: now) == Date(timeIntervalSince1970: 1_791_902_700 + 300))
    }

    @Test func aPausedMemberCountsAsResumingNow() {
        let state = State(v: 1, m: [
            member("ava", .focusing, end: now.timeIntervalSince1970 + 600),
            member("kai", .paused, end: now.timeIntervalSince1970 + 5_000, pausedAt: now.timeIntervalSince1970 - 1_000),
        ])
        // Kai froze with 6,000 s left; resuming now would end at now + 6,000.
        #expect(state.staleDate(now: now) == now.addingTimeInterval(6_000 + 300))
        // Later, still paused: the stale date moves with now.
        let later = now.addingTimeInterval(1_000)
        #expect(state.staleDate(now: later) == later.addingTimeInterval(6_000 + 300))
    }

    @Test func withNobodyActiveTheLatestEndIsUsed() {
        let state = State(v: 9, m: [
            member("ava", .done, end: 1_000),
            member("noor", .left, end: 3_000),
            member("kai", .slipped, end: 2_000),
        ])
        #expect(state.staleDate(now: now) == Date(timeIntervalSince1970: 3_300))
    }

    @Test func emptyStatesGoStaleFromNow() {
        let state = State(v: 1, m: [])
        #expect(state.staleDate(now: now) == now.addingTimeInterval(LiveActivityLimits.staleGraceSeconds))
        #expect(state.latestEnd == nil)
    }

    @Test func latestEndLooksAtEveryone() throws {
        let state = try Fixture.contentState("squad-6")
        #expect(state.latestEnd == Date(timeIntervalSince1970: 1_791_903_060))
    }

    @Test func orderedPutsMeFirstAndKeepsServerOrder() throws {
        let state = try Fixture.contentState("squad-6")
        let names = { (members: [Member]) in members.map(\.n) }

        #expect(names(state.ordered(meFirst: "Ka9Lm3Vx0c")) == ["Kai", "Ava", "Noor", "Mateo", "Sakura", "Jules"])
        #expect(names(state.ordered(meFirst: "Jl3Bt8Gc2f")) == ["Jules", "Ava", "Noor", "Kai", "Mateo", "Sakura"])
        #expect(names(state.ordered(meFirst: "Av4Nq8sT2b")) == ["Ava", "Noor", "Kai", "Mateo", "Sakura", "Jules"])
        // Not in the room (yet): server order.
        #expect(names(state.ordered(meFirst: "nobody0000")) == ["Ava", "Noor", "Kai", "Mateo", "Sakura", "Jules"])
    }

    @Test func othersFocusingCountsOnlyOthersWhoAreFocusing() throws {
        let state = State(v: 1, m: [
            member("me", .focusing, end: 0),
            member("ava", .focusing, end: 0),
            member("noor", .focusing, end: 0),
            member("kai", .onBreak, end: 0),
            member("jules", .paused, end: 0),
            member("mateo", .done, end: 0),
        ])
        #expect(state.othersFocusing(excluding: "me") == 2)
        #expect(state.othersFocusing(excluding: "kai") == 3)
        #expect(state.othersFocusing(excluding: "stranger") == 3)

        // In squad-6 Ava is the only one focusing.
        let squad = try Fixture.contentState("squad-6")
        #expect(squad.othersFocusing(excluding: "Av4Nq8sT2b") == 0)
        #expect(squad.othersFocusing(excluding: "Nr2Kx7pQ1m") == 1)
    }

    @Test func findsMembersById() throws {
        let state = try Fixture.contentState("squad-6")
        #expect(state.member(id: "Mt5Rw1Zy8d")?.n == "Mateo")
        #expect(state.member(id: "Mt5Rw1Zy8d")?.state == .done)
        #expect(state.member(id: "nobody0000") == nil)
    }

    @Test func soloStateIsVersionOneWithoutPetOrCheer() throws {
        let ava = member("Av4Nq8sT2b", .focusing, end: now.timeIntervalSince1970 + 1_500)
        let state = State.solo(member: ava)
        #expect(state == State(v: 1, m: [ava], p: nil, c: nil))
        let keys = try Fixture.keys(JSONEncoder().encode(state))
        #expect(keys == ["v", "m"])
    }

    @Test func soloAttributesHaveALocalSessionId() {
        let attributes = LockinAttributes.solo(me: "Av4Nq8sT2b")
        #expect(attributes.me == "Av4Nq8sT2b")
        #expect(attributes.sq == nil)
        #expect(attributes.isSolo)
        #expect(attributes.sid.count == 10)
        let alphanumeric = attributes.sid.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        #expect(alphanumeric)
        #expect(LockinAttributes.solo(me: "Av4Nq8sT2b", sid: "s0LoRun123").sid == "s0LoRun123")
    }

    @Test func petValuesAreHeldInRange() {
        typealias Pet = LockinAttributes.ContentState.Pet
        #expect(Pet(k: "fox.2", md: -1, x: -0.5).mood == 0)
        #expect(Pet(k: "fox.2", md: -1, x: -0.5).progress == 0)
        #expect(Pet(k: "fox.2", md: 7, x: 1.5).mood == 3)
        #expect(Pet(k: "fox.2", md: 7, x: 1.5).progress == 1)
        #expect(Pet(k: "fox.2", md: 2, x: 0.64).progress == 0.64)
        #expect(Pet(k: "fox.2", md: 2, x: .nan).progress == 0)
        #expect(Pet(k: "fox.2", md: 2, x: 0.64).code == PetCode(species: "fox", stage: 2))
    }

    @Test func cheerDate() {
        let cheer = LockinAttributes.ContentState.Cheer(f: "Nr2Kx7pQ1m", t: "Av4Nq8sT2b", k: 3, at: 1_791_900_650)
        #expect(cheer.date == Date(timeIntervalSince1970: 1_791_900_650))
    }
}
