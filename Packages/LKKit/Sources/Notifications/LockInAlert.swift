import Foundation

/// The app's part of an "is locking in" alert: the `lk` dictionary beside `aps`
/// (docs/milestones/M4.md), `{ "type": "lockin", "sid": "<sessionId>", "sq": "<squadId>" }`.
public struct LockInAlert: Hashable, Sendable {
    /// The key of the app's dictionary in the push payload.
    public static let payloadKey = "lk"
    /// `lk.type` of an "is locking in" alert.
    public static let type = "lockin"

    /// The room that just opened: Join 25 and Join 50 join it (`POST /sessions/:id/join`).
    public var sessionId: String
    /// The room's squad: a tap on the alert opens Home with it picked.
    public var squadId: String

    public init(sessionId: String, squadId: String) {
        self.sessionId = sessionId
        self.squadId = squadId
    }

    /// Reads a notification's `userInfo`. Nil unless it carries an `lk` dictionary with a session
    /// and a squad id.
    ///
    /// Lenient, so an alert never fails over something it doesn't need: extra keys are ignored,
    /// and a missing `type` reads as "lockin". Another type (one a later server adds) isn't one.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let payload = Self.dictionary(userInfo[Self.payloadKey]) else { return nil }
        if let type = payload["type"] {
            guard (type as? String) == Self.type else { return nil }
        }
        guard let sessionId = Self.id(payload["sid"]), let squadId = Self.id(payload["sq"]) else { return nil }
        self.init(sessionId: sessionId, squadId: squadId)
    }

    /// The payload's `lk` part, as the server sends it. For tests and previews.
    public var userInfo: [AnyHashable: Any] {
        [Self.payloadKey: ["type": Self.type, "sid": sessionId, "sq": squadId]]
    }

    /// Ids are the server's short ids. Anything that isn't a short, non-empty string is no id.
    static let maxIDLength = 64

    private static func id(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxIDLength else { return nil }
        return trimmed
    }

    /// A dictionary with string keys, from whichever form it arrived in: Foundation's from a real
    /// push, Swift's from a test.
    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let dictionary = value as? [AnyHashable: Any] else { return nil }
        var strings: [String: Any] = [:]
        for (key, value) in dictionary {
            if let key = key.base as? String {
                strings[key] = value
            }
        }
        return strings
    }
}
