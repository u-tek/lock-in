import Foundation
import Model
import Testing
@testable import LiveActivity

/// The wire fixtures in `fixtures/live-activity/` at the repository root, read the way
/// ModelTests reads them, so the samples can be checked against the files the server tests too.
enum Fixture {
    struct NotFound: Error, CustomStringConvertible {
        var description: String
    }

    /// Walks up from this source file to the directory holding `fixtures/live-activity`.
    static func directory() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in url.pathComponents.indices {
            let candidate = url.appendingPathComponent("fixtures/live-activity", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            url = url.deletingLastPathComponent()
        }
        throw NotFound(description: "No fixtures/live-activity above \(#filePath)")
    }

    /// Decoded with a plain `JSONDecoder()`, as ActivityKit decodes a push.
    static func attributes(_ name: String) throws -> LockinAttributes {
        let data = try Data(contentsOf: directory().appendingPathComponent("\(name).attributes.json"))
        return try JSONDecoder().decode(LockinAttributes.self, from: data)
    }

    static func contentState(_ name: String) throws -> LockinAttributes.ContentState {
        let data = try Data(contentsOf: directory().appendingPathComponent("\(name).content-state.json"))
        return try JSONDecoder().decode(LockinAttributes.ContentState.self, from: data)
    }
}

@Suite struct SampleTests {
    private let fixtureDate = LiveActivitySamples.fixtureDate

    // MARK: Mirrors of the fixtures

    @Test func squadOfSixMirrorsItsFixture() throws {
        let sample = LiveActivitySamples.squadOfSix(now: fixtureDate)
        let attributes = try Fixture.attributes("squad-6")
        let state = try Fixture.contentState("squad-6")
        #expect(sample.id == "squad-6")
        #expect(sample.attributes == attributes)
        #expect(sample.state == state)
    }

    @Test func soloMirrorsItsFixture() throws {
        let sample = LiveActivitySamples.solo(now: fixtureDate)
        let attributes = try Fixture.attributes("solo")
        let state = try Fixture.contentState("solo")
        #expect(sample.attributes == attributes)
        #expect(sample.state == state)
    }

    @Test func largestMirrorsItsFixture() throws {
        let sample = LiveActivitySamples.largest(now: fixtureDate)
        let attributes = try Fixture.attributes("largest")
        let state = try Fixture.contentState("largest")
        #expect(sample.attributes == attributes)
        #expect(sample.state == state)
    }

    // MARK: Live timers

    @Test func everyTimeFollowsNow() {
        let later = fixtureDate.addingTimeInterval(3_600)
        let pairs = zip(LiveActivitySamples.catalogue(now: fixtureDate), LiveActivitySamples.catalogue(now: later))
        for (before, after) in pairs {
            #expect(before.id == after.id)
            #expect(before.attributes == after.attributes)
            #expect(before.state.m.count == after.state.m.count)
            for (a, b) in zip(before.state.m, after.state.m) {
                #expect(b.b == a.b + 3_600)
                #expect(b.e == a.e + 3_600)
                #expect(b.q == a.q.map { $0 + 3_600 })
            }
            #expect(after.state.c?.at == before.state.c.map { $0.at + 3_600 })
        }
    }

    @Test func timersAreRunningAtNow() {
        // Every focusing member in the Lab is mid-session: started before now, ending after it.
        let now = Date()
        let t = now.timeIntervalSince1970
        for sample in LiveActivitySamples.catalogue(now: now) {
            for member in sample.state.m where member.state == .focusing {
                #expect(member.b < t, "\(sample.id): \(member.n) starts after now")
                #expect(member.e > t, "\(sample.id): \(member.n) has already finished")
            }
        }
    }

    // MARK: The catalogue

    @Test func catalogueIsWithinTheBudget() {
        for now in [fixtureDate, Date()] {
            for sample in LiveActivitySamples.catalogue(now: now) {
                #expect(sample.attributes.fitsPayloadBudget(sample.state), "\(sample.id) is over budget")
                #expect(sample.state.m.count <= LiveActivityLimits.maxMembers)
                #expect(sample.state.member(id: sample.attributes.me) != nil, "\(sample.id) doesn't include me")
            }
        }
    }

    @Test func catalogueIdsAreUniqueAndFileNameSafe() {
        let ids = LiveActivitySamples.catalogue(now: fixtureDate).map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            let safe = id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            #expect(safe, "\(id)")
        }
    }

    @Test func soloSamplesCoverEveryState() {
        let solo = LiveActivitySamples.catalogue(now: fixtureDate).filter { $0.attributes.isSolo }
        let states = solo.compactMap { $0.presentation.primary?.state }
        #expect(Set(states) == Set(MemberState.allCases))
        #expect(states.count == MemberState.allCases.count)
    }

    @Test(arguments: MemberState.allCases)
    func squadOfSixWithMeInEachState(state: MemberState) throws {
        let sample = LiveActivitySamples.squadOfSix(now: fixtureDate, me: state)
        let primary = try #require(sample.presentation.primary)
        #expect(primary.isMe)
        #expect(primary.state == state)
        #expect(sample.attributes.fitsPayloadBudget(sample.state))
        let ids: [MemberState: String] = [
            .focusing: "squad-6",
            .onBreak: "squad-6-break",
            .paused: "squad-6-paused",
            .done: "squad-6-done",
            .left: "squad-6-left",
            .slipped: "squad-6-slipped",
        ]
        #expect(sample.id == ids[state])
    }

    @Test func squadOfFourShowsPlusThree() {
        let presentation = LiveActivitySamples.squadOfFour(now: fixtureDate).presentation
        #expect(presentation.compactTrailing == .squadmates(3))
        #expect(presentation.compactTrailing.staticText == "+3")
        #expect(presentation.focusingCount == 4)
        // Mateo's 90 minutes needs the hours digit.
        let mateo = presentation.members.first { $0.name == "Mateo" }
        #expect(mateo?.countdown.needsHours == true)
    }

    @Test func pausedSoloIsFrozenAtSeventeenMinutes() throws {
        let presentation = LiveActivitySamples.solo(now: fixtureDate, me: .paused).presentation
        let me = try #require(presentation.primary)
        #expect(me.countdown.frozenRemaining == 1_020)
        #expect(me.accessibilityLabel == "Ava, you, paused, 17 minutes left")
        // Paused 8 minutes into 25.
        #expect(presentation.sessionProgress == .fixed(480.0 / 1_500.0))
    }
}
