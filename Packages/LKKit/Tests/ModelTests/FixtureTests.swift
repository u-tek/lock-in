import Foundation
import Testing
@testable import Model

/// The shared wire-format fixtures in `fixtures/live-activity/` at the repository root. The server
/// tests read the same files, so if either side renames, drops or adds a key, one of them fails.
enum Fixture {
    static let names = ["squad-6", "solo", "largest"]

    enum Part: String {
        case attributes
        case contentState = "content-state"
    }

    struct NotFound: Error, CustomStringConvertible {
        var description: String
    }

    /// Walks up from this source file to the directory holding `fixtures/live-activity`, so the
    /// tests don't depend on how deep the package sits in the repository.
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

    static func data(_ name: String, _ part: Part) throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent("\(name).\(part.rawValue).json"))
    }

    /// Decoded exactly the way ActivityKit decodes a push: a plain `JSONDecoder()`.
    static func attributes(_ name: String) throws -> LockinAttributes {
        try JSONDecoder().decode(LockinAttributes.self, from: data(name, .attributes))
    }

    static func contentState(_ name: String) throws -> LockinAttributes.ContentState {
        try JSONDecoder().decode(LockinAttributes.ContentState.self, from: data(name, .contentState))
    }

    /// JSON as Foundation objects, for comparing documents regardless of key order, whitespace and
    /// number formatting (`1791900000` and `1791900000.0` are the same number).
    static func object(_ data: Data) throws -> NSDictionary {
        guard let object = try JSONSerialization.jsonObject(with: data) as? NSDictionary else {
            throw NotFound(description: "Not a JSON object")
        }
        return object
    }

    static func keys(_ data: Data) throws -> Set<String> {
        let dictionary = try object(data)
        return Set(dictionary.allKeys.compactMap { $0 as? String })
    }
}

@Suite struct FixtureTests {
    @Test(arguments: Fixture.names)
    func contentStateSurvivesARoundTrip(name: String) throws {
        let original = try Fixture.data(name, .contentState)
        let state = try JSONDecoder().decode(LockinAttributes.ContentState.self, from: original)
        let reencoded = try JSONEncoder().encode(state)

        // Nothing dropped, renamed or added; optional keys that were absent stay absent.
        let before = try Fixture.object(original)
        let after = try Fixture.object(reencoded)
        #expect(after == before)
        #expect(!String(decoding: reencoded, as: UTF8.self).contains("null"))
    }

    @Test(arguments: Fixture.names)
    func attributesSurviveARoundTrip(name: String) throws {
        let original = try Fixture.data(name, .attributes)
        let attributes = try JSONDecoder().decode(LockinAttributes.self, from: original)
        let reencoded = try JSONEncoder().encode(attributes)

        let before = try Fixture.object(original)
        let after = try Fixture.object(reencoded)
        #expect(after == before)
        #expect(!String(decoding: reencoded, as: UTF8.self).contains("null"))
    }

    @Test(arguments: Fixture.names)
    func everyFixtureFitsThePayloadBudget(name: String) throws {
        let attributes = try Fixture.attributes(name)
        let state = try Fixture.contentState(name)
        #expect(attributes.fitsPayloadBudget(state))
        #expect(state.m.count <= LiveActivityLimits.maxMembers)
    }

    @Test func squadOfSixHasOneMemberInEachState() throws {
        let state = try Fixture.contentState("squad-6")
        #expect(state.m.count == 6)
        #expect(Set(state.m.map(\.state)) == Set(MemberState.allCases))
        #expect(state.p != nil)
        #expect(state.c != nil)
        // Only the paused member carries a paused-at time.
        let withPausedAt = state.m.filter { $0.q != nil }.map(\.state)
        #expect(withPausedAt == [.paused])
        let attributes = try Fixture.attributes("squad-6")
        #expect(attributes.sq == "Library Goblins")
    }

    @Test func soloHasNoSquadPetOrCheer() throws {
        let attributes = try Fixture.attributes("solo")
        let state = try Fixture.contentState("solo")
        #expect(attributes.sq == nil)
        #expect(attributes.isSolo)
        #expect(state.p == nil)
        #expect(state.c == nil)

        // Re-encoded, the optional keys are left out rather than written as null.
        let member = try #require(state.m.first)
        let attributeKeys = try Fixture.keys(JSONEncoder().encode(attributes))
        let stateKeys = try Fixture.keys(JSONEncoder().encode(state))
        let memberKeys = try Fixture.keys(JSONEncoder().encode(member))
        #expect(attributeKeys == ["sid", "me"])
        #expect(stateKeys == ["v", "m"])
        #expect(memberKeys == ["i", "n", "a", "s", "b", "e"])
    }

    @Test func largestIsTheWorstCaseTheLimitsAllow() throws {
        let attributes = try Fixture.attributes("largest")
        let state = try Fixture.contentState("largest")

        // Every limit at its maximum, every optional key present...
        #expect(state.m.count == LiveActivityLimits.maxMembers)
        #expect(attributes.sq?.unicodeScalars.count == LiveActivityLimits.maxSquadNameLength)
        for member in state.m {
            #expect(member.n.unicodeScalars.count == LiveActivityLimits.maxNameLength)
            #expect(member.q != nil)
        }
        #expect(state.p != nil)
        #expect(state.c != nil)

        // ...and still within budget. About 1.2 KB: the lower bound checks something was measured.
        let bytes = attributes.payloadByteCount(for: state)
        #expect(bytes > 1_100)
        #expect(bytes <= LiveActivityLimits.payloadBudgetBytes)
    }
}

@Suite struct WireFormatTests {
    @Test func newerPayloadsStillDecode() throws {
        // A newer server: an unknown member state, an extra avatar part, extra keys and an
        // explicit null. An old app must still show everyone.
        let json = """
        {"v":7,"m":[{"i":"Av4Nq8sT2b","n":"Ava","a":"b3.c7.e2.h4.w9","s":9,"b":1791900000,"e":1791901500,"z":1}],
         "p":null,"c":null,"r":{"new":true}}
        """
        let state = try JSONDecoder().decode(LockinAttributes.ContentState.self, from: Data(json.utf8))
        let member = try #require(state.m.first)
        #expect(member.state == .focusing)
        #expect(member.avatar == AvatarCode(body: 3, colour: 7, eyes: 2, hat: 4))
        #expect(state.p == nil)
        #expect(state.c == nil)
    }

    @Test func timesAreNumbersNotDates() throws {
        let member = LockinAttributes.ContentState.Member(i: "Av4Nq8sT2b", n: "Ava", a: "b3.c7.e2.h4", s: 0, b: 1_791_900_000.5, e: 1_791_901_500)
        let object = try Fixture.object(JSONEncoder().encode(member))
        #expect(object["b"] is NSNumber)
        #expect((object["b"] as? NSNumber)?.doubleValue == 1_791_900_000.5)
        #expect((object["e"] as? NSNumber)?.doubleValue == 1_791_901_500)
    }

    @Test func oversizeStatesAreCaught() {
        let attributes = LockinAttributes(sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b", sq: "Library Goblins")
        let longName = String(repeating: "x", count: 1_000)
        let members = (0..<6).map { index in
            LockinAttributes.ContentState.Member(i: "member000\(index)", n: longName, a: "b0.c0.e0.h0", s: 0, b: 0, e: 1)
        }
        let state = LockinAttributes.ContentState(v: 1, m: members)
        #expect(attributes.payloadByteCount(for: state) > LiveActivityLimits.systemLimitBytes)
        #expect(!attributes.fitsPayloadBudget(state))
    }

    @Test func unencodableStatesNeverFit() {
        let attributes = LockinAttributes(sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b")
        let member = LockinAttributes.ContentState.Member(i: "Av4Nq8sT2b", n: "Ava", a: "b0", s: 0, b: .nan, e: .infinity)
        let state = LockinAttributes.ContentState.solo(member: member)
        #expect(attributes.payloadByteCount(for: state) == Int.max)
        #expect(!attributes.fitsPayloadBudget(state))
    }
}
