import Foundation

/// The Live Activity's data: SPEC.md §4.3, key for key.
///
/// This is a wire format shared with the server (`server/src/liveActivity.ts`) and pinned by the
/// files in `fixtures/live-activity/`. ActivityKit decodes pushed content-state with a plain
/// `JSONDecoder()`, so:
/// - property names are the JSON keys (short, because the payload is capped at 4 KB);
/// - Codable is synthesised, never customised, so keys can't drift from the property names;
/// - times are `Double` Unix seconds, never `Date`;
/// - optional values are left out when nil (synthesised `encodeIfPresent`), never sent as null.
///
/// The readable accessors live in `LockinAttributes+Helpers.swift`. Change a key here, in the
/// fixtures and in the server in the same commit.
public struct LockinAttributes: Codable, Hashable, Sendable {
    // Static: set when this device starts the activity, never changed by a push.

    /// Session (room) id.
    public let sid: String
    /// This device owner's member id, so one content-state serves every member of the room.
    public let me: String
    /// Squad name, at most 20 characters. Nil for a solo session.
    public let sq: String?

    public init(sid: String, me: String, sq: String? = nil) {
        self.sid = sid
        self.me = me
        self.sq = sq
    }

    /// Dynamic: replaced by every update, pushed or local. Identical for every member of a room.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Monotonically increasing state version, so a late push can't roll the view back.
        public var v: Int
        /// At most 6, in server order (host first). Views put `me` first.
        public var m: [Member]
        /// The squad pet. Nil when solo.
        public var p: Pet?
        /// The most recent cheer, shown briefly.
        public var c: Cheer?

        public init(v: Int, m: [Member], p: Pet? = nil, c: Cheer? = nil) {
            self.v = v
            self.m = m
            self.p = p
            self.c = c
        }

        public struct Member: Codable, Hashable, Sendable {
            /// Member id.
            public var i: String
            /// Display name, at most 12 characters.
            public var n: String
            /// Avatar code, e.g. "b3.c7.e2.h4" (see `AvatarCode`).
            public var a: String
            /// State: 0 focusing, 1 break, 2 paused, 3 done, 4 left, 5 slipped (see `MemberState`).
            public var s: Int
            /// Started at, Unix seconds.
            public var b: Double
            /// Ends at, Unix seconds. While paused, the time left is `e - q`.
            public var e: Double
            /// Paused at, Unix seconds. Only while paused.
            public var q: Double?

            public init(i: String, n: String, a: String, s: Int, b: Double, e: Double, q: Double? = nil) {
                self.i = i
                self.n = n
                self.a = a
                self.s = s
                self.b = b
                self.e = e
                self.q = q
            }
        }

        public struct Pet: Codable, Hashable, Sendable {
            /// Species and stage code, e.g. "fox.2" (see `PetCode`).
            public var k: String
            /// Mood, 0–3.
            public var md: Int
            /// Progress to the next stage, 0–1.
            public var x: Double

            public init(k: String, md: Int, x: Double) {
                self.k = k
                self.md = md
                self.x = x
            }
        }

        public struct Cheer: Codable, Hashable, Sendable {
            /// From member id.
            public var f: String
            /// To member id.
            public var t: String
            /// Cheer kind (index into the emoji set).
            public var k: Int
            /// Sent at, Unix seconds.
            public var at: Double

            public init(f: String, t: String, k: Int, at: Double) {
                self.f = f
                self.t = t
                self.k = k
                self.at = at
            }
        }
    }
}
