import Core
import Foundation

// Readable accessors over the short wire keys. Everything here is computed, so none of it reaches
// the JSON: synthesised Codable only encodes stored properties.

extension LockinAttributes {
    /// Attributes for a solo session, which has no room on the server: the session id is made
    /// locally.
    public static func solo(me: String, sid: String = ShortID.make()) -> LockinAttributes {
        LockinAttributes(sid: sid, me: me, sq: nil)
    }

    public var isSolo: Bool {
        sq == nil
    }

    /// Bytes of attributes + `state` as compact JSON, encoded the way ActivityKit and the server
    /// see them. `Int.max` when the state can't be encoded at all (a non-finite time), which no
    /// budget accepts.
    public func payloadByteCount(for state: ContentState) -> Int {
        let encoder = JSONEncoder()
        guard let attributes = try? encoder.encode(self),
              let content = try? encoder.encode(state)
        else { return Int.max }
        return attributes.count + content.count
    }

    /// Within our 3.5 KB budget (`LiveActivityLimits.payloadBudgetBytes`).
    public func fitsPayloadBudget(_ state: ContentState) -> Bool {
        payloadByteCount(for: state) <= LiveActivityLimits.payloadBudgetBytes
    }
}

extension LockinAttributes.ContentState {
    /// The first state of a solo session: version 1, no pet, no cheer.
    public static func solo(member: Member) -> LockinAttributes.ContentState {
        LockinAttributes.ContentState(v: 1, m: [member], p: nil, c: nil)
    }

    public func member(id: String) -> Member? {
        m.first { $0.i == id }
    }

    /// Members for display: `me` first, everyone else in server order (host first).
    public func ordered(meFirst me: String) -> [Member] {
        guard let index = m.firstIndex(where: { $0.i == me }) else { return m }
        var members = m
        let mine = members.remove(at: index)
        members.insert(mine, at: 0)
        return members
    }

    /// Squadmates focusing right now: the "+3" in the compact island.
    public func othersFocusing(excluding me: String) -> Int {
        m.filter { $0.i != me && $0.state == .focusing }.count
    }

    /// The latest scheduled end across every member.
    public var latestEnd: Date? {
        m.map(\.e).max().map { Date(timeIntervalSince1970: $0) }
    }

    /// When the activity should show as out of date if no further update arrives: 5 minutes after
    /// the last running timer should end (SPEC.md §4.4).
    ///
    /// A paused timer has no end yet, so it counts as resuming now (`now` + its remaining time).
    /// Members who are done, left or slipped don't hold the activity open unless nobody is active,
    /// in which case the latest end of anyone is used.
    public func staleDate(now: Date) -> Date {
        let running = m.filter { $0.state.isActive }
        let considered = running.isEmpty ? m : running
        let ends = considered.map { member -> TimeInterval in
            member.state == .paused
                ? now.timeIntervalSince1970 + member.remaining(at: now)
                : member.e
        }
        guard let latest = ends.max() else {
            return now.addingTimeInterval(LiveActivityLimits.staleGraceSeconds)
        }
        return Date(timeIntervalSince1970: latest + LiveActivityLimits.staleGraceSeconds)
    }
}

extension LockinAttributes.ContentState.Member {
    /// The same member with readable labels and `Date`s, for building states in the app, the Lab
    /// and tests.
    public init(
        id: String,
        name: String,
        avatar: AvatarCode = .default,
        state: MemberState = .focusing,
        start: Date,
        end: Date,
        pausedAt: Date? = nil
    ) {
        self.init(
            i: id,
            n: name,
            a: avatar.code,
            s: state.rawValue,
            b: start.timeIntervalSince1970,
            e: end.timeIntervalSince1970,
            q: pausedAt?.timeIntervalSince1970
        )
    }

    /// The state, with values from a newer server read as `.focusing` so an old app never fails
    /// to show a member.
    public var state: MemberState {
        get { MemberState(rawValue: s) ?? .focusing }
        set { s = newValue.rawValue }
    }

    public var isActive: Bool {
        state.isActive
    }

    public var avatar: AvatarCode {
        AvatarCode(a)
    }

    public var startDate: Date {
        Date(timeIntervalSince1970: b)
    }

    public var endDate: Date {
        Date(timeIntervalSince1970: e)
    }

    public var pausedDate: Date? {
        q.map { Date(timeIntervalSince1970: $0) }
    }

    /// Seconds left on the timer at `date`, never negative.
    ///
    /// A paused timer is frozen at the moment it was paused, so it reports `e - q` whatever the
    /// date. This doesn't look at other states: check `isActive` before showing it.
    public func remaining(at date: Date) -> TimeInterval {
        let reference = (state == .paused ? q : nil) ?? date.timeIntervalSince1970
        return max(0, e - reference)
    }

    /// Start to end, for `Text(timerInterval:)`. Never inverted, which would trap in
    /// `ClosedRange`: an end before the start (or a non-finite time) collapses to the start.
    public var timerRange: ClosedRange<Date> {
        let start = b.isFinite ? b : 0
        let end = e.isFinite ? max(start, e) : start
        return Date(timeIntervalSince1970: start)...Date(timeIntervalSince1970: end)
    }
}

extension LockinAttributes.ContentState.Pet {
    public var code: PetCode {
        PetCode(k)
    }

    /// `md` held to 0–3.
    public var mood: Int {
        min(max(md, 0), 3)
    }

    /// `x` held to 0–1.
    public var progress: Double {
        x.isFinite ? min(max(x, 0), 1) : 0
    }
}

extension LockinAttributes.ContentState.Cheer {
    public var date: Date {
        Date(timeIntervalSince1970: at)
    }
}
