import Foundation
import Model

/// One fake activity, for the Live Activity Lab and previews.
public struct LiveActivitySample: Hashable, Sendable, Identifiable {
    /// Stable and file-name safe ("squad-6", "solo-paused"), so the Lab can name snapshots by it.
    public let id: String
    /// What the Lab's heading says.
    public let title: String
    public let attributes: LockinAttributes
    public let state: LockinAttributes.ContentState

    public init(id: String, title: String, attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        self.id = id
        self.title = title
        self.attributes = attributes
        self.state = state
    }

    public var presentation: LiveActivityPresentation {
        LiveActivityPresentation(attributes: attributes, state: state)
    }
}

/// Fake squads that mirror the wire fixtures in `fixtures/live-activity/`, with every time
/// relative to `now`, so timers in the Lab and in previews are live rather than long finished.
///
/// At `fixtureDate` the mirrors equal their fixtures exactly (LiveActivityTests checks it), so the
/// Lab draws what the server's tests encode. Every sample is within the payload budget.
public enum LiveActivitySamples {
    /// Ten minutes into the fixtures' session: Ava's 25 minutes started at 1_791_900_000.
    public static let fixtureDate = Date(timeIntervalSince1970: 1_791_900_600)

    /// Every sample the Lab shows: the squad of six (one member in each state), a squad of four
    /// all focusing (the "+3" island), a solo session with you in each state, and the largest
    /// payload the server allows.
    public static func catalogue(now: Date = Date()) -> [LiveActivitySample] {
        [squadOfSix(now: now), squadOfFour(now: now)]
            + MemberState.allCases.map { solo(now: now, me: $0) }
            + [largest(now: now)]
    }

    /// `squad-6`: Ava (you), Noor on a break, Kai paused, Mateo done, Sakura left, Jules slipped,
    /// a teen pet and a cheer. Nobody but you is focusing, so the compact island shows your time.
    /// The pet is the fixture's "fox", from before the species were named (M5): this version
    /// draws a species it doesn't know as a puff.
    ///
    /// - Parameter state: Your state. Anything but `.focusing` changes your times to suit it, and
    ///   the sample no longer mirrors the fixture.
    public static func squadOfSix(now: Date = Date(), me state: MemberState = .focusing) -> LiveActivitySample {
        let t = now.timeIntervalSince1970
        let members = [
            ava(state, at: t),
            Member(i: "Nr2Kx7pQ1m", n: "Noor", a: "b1.c2.e5.h0", s: MemberState.onBreak.rawValue, b: t - 900, e: t + 2_100),
            Member(i: "Ka9Lm3Vx0c", n: "Kai", a: "b2.c4.e1.h2", s: MemberState.paused.rawValue, b: t - 720, e: t + 780, q: t),
            Member(i: "Mt5Rw1Zy8d", n: "Mateo", a: "b4.c1.e3.h1", s: MemberState.done.rawValue, b: t - 2_600, e: t - 1_100),
            Member(i: "Sk7Pj4Hn6e", n: "Sakura", a: "b0.c5.e4.h3", s: MemberState.left.rawValue, b: t - 1_600, e: t + 1_400),
            Member(i: "Jl3Bt8Gc2f", n: "Jules", a: "b5.c3.e0.h5", s: MemberState.slipped.rawValue, b: t - 540, e: t + 2_460),
        ]
        let isFixture = state == .focusing
        return LiveActivitySample(
            id: isFixture ? "squad-6" : "squad-6-\(key(state))",
            title: isFixture ? "Squad of 6, one in every state" : "Squad of 6 · You: \(title(state))",
            attributes: LockinAttributes(sid: "r7Kq2xP9aL", me: avaID, sq: "Library Goblins"),
            state: LockinAttributes.ContentState(
                v: 42,
                m: members,
                p: LockinAttributes.ContentState.Pet(k: "fox.2", md: 2, x: 0.64),
                c: LockinAttributes.ContentState.Cheer(f: "Nr2Kx7pQ1m", t: avaID, k: 3, at: t + 50)
            )
        )
    }

    /// `squad-4`: a free squad, everyone focusing, so the compact island reads "+3". Mateo's
    /// 90 minutes needs the hours digit. Their pet is a baby sprout having a happy day.
    public static func squadOfFour(now: Date = Date()) -> LiveActivitySample {
        let t = now.timeIntervalSince1970
        let focusing = MemberState.focusing.rawValue
        return LiveActivitySample(
            id: "squad-4",
            title: "Squad of 4, all locked in",
            attributes: LockinAttributes(sid: "q4Lm8Rt2Wx", me: avaID, sq: "Library Goblins"),
            state: LockinAttributes.ContentState(
                v: 7,
                m: [
                    ava(.focusing, at: t),
                    Member(i: "Nr2Kx7pQ1m", n: "Noor", a: "b1.c2.e5.h0", s: focusing, b: t - 300, e: t + 2_700),
                    Member(i: "Ka9Lm3Vx0c", n: "Kai", a: "b2.c4.e1.h2", s: focusing, b: t - 1_200, e: t + 300),
                    Member(i: "Mt5Rw1Zy8d", n: "Mateo", a: "b4.c1.e3.h1", s: focusing, b: t - 60, e: t + 5_340),
                ],
                p: LockinAttributes.ContentState.Pet(k: "sprout.1", md: 3, x: 0.2)
            )
        )
    }

    /// `solo`: you alone, no squad, pet or cheer.
    ///
    /// - Parameter state: Your state. `.focusing` mirrors the fixture.
    public static func solo(now: Date = Date(), me state: MemberState = .focusing) -> LiveActivitySample {
        LiveActivitySample(
            id: "solo-\(key(state))",
            title: "Solo · \(title(state))",
            attributes: LockinAttributes(sid: "s0LoRun123", me: avaID),
            state: LockinAttributes.ContentState(v: 1, m: [ava(state, at: now.timeIntervalSince1970)])
        )
    }

    /// `largest`: every limit at its maximum. Six paused members with twelve-emoji names, a
    /// twenty-emoji squad name, the longest times. Its pauses fall about two hours after `now`,
    /// so the Lab shows its timers running at their widest (about "3:50:00").
    public static func largest(now: Date = Date()) -> LiveActivitySample {
        let t = now.timeIntervalSince1970
        let members = (0..<LiveActivityLimits.maxMembers).map { index -> Member in
            let offset = Double(index)
            return Member(
                i: "zZ9yY8xX7\(index)",
                n: String(repeating: "🦊", count: LiveActivityLimits.maxNameLength),
                a: "b99.c99.e99.h99",
                s: MemberState.paused.rawValue,
                b: t - 599.875 + offset,
                e: t + 13_800.125 + offset,
                q: t + 6_600.125 + offset
            )
        }
        return LiveActivitySample(
            id: "largest",
            title: "Largest payload",
            attributes: LockinAttributes(
                sid: "zZ9yY8xX7w",
                me: "zZ9yY8xX70",
                sq: String(repeating: "🔒", count: LiveActivityLimits.maxSquadNameLength)
            ),
            state: LockinAttributes.ContentState(
                v: Int(Int32.max),
                m: members,
                p: LockinAttributes.ContentState.Pet(k: "dragonling.12", md: 3, x: 0.987654321),
                c: LockinAttributes.ContentState.Cheer(f: "zZ9yY8xX71", t: "zZ9yY8xX70", k: 11, at: t + 6_600.125)
            )
        )
    }

    // MARK: - Helpers

    private typealias Member = LockinAttributes.ContentState.Member

    /// Ava's member id: "me" in every sample but `largest`.
    private static let avaID = "Av4Nq8sT2b"

    /// Ava in `state` at `t`, with times that suit the state. Focusing is the fixtures' Ava, ten
    /// minutes into 25.
    private static func ava(_ state: MemberState, at t: TimeInterval) -> Member {
        let s = state.rawValue
        switch state {
        case .focusing, .left, .slipped:
            return Member(i: avaID, n: "Ava", a: "b3.c7.e2.h4", s: s, b: t - 600, e: t + 900)
        case .onBreak:
            // One minute into a five-minute break.
            return Member(i: avaID, n: "Ava", a: "b3.c7.e2.h4", s: s, b: t - 60, e: t + 240)
        case .paused:
            // Paused two minutes ago with 17 minutes to go, so it reads differently from a
            // running timer at the same moment (15 minutes).
            return Member(i: avaID, n: "Ava", a: "b3.c7.e2.h4", s: s, b: t - 600, e: t + 900, q: t - 120)
        case .done:
            return Member(i: avaID, n: "Ava", a: "b3.c7.e2.h4", s: s, b: t - 1_500, e: t)
        }
    }

    /// A state as a file-name-safe word, as in the wire comment (SPEC.md §4.3).
    private static func key(_ state: MemberState) -> String {
        switch state {
        case .focusing: return "focusing"
        case .onBreak: return "break"
        case .paused: return "paused"
        case .done: return "done"
        case .left: return "left"
        case .slipped: return "slipped"
        }
    }

    private static func title(_ state: MemberState) -> String {
        LiveActivityPresentation.tone(for: state).title
    }
}
