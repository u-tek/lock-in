import Core
import Foundation
import Model

// The JSON the API speaks (docs/milestones/M2.md). Keys are camelCase and match these properties
// exactly, so plain `JSONDecoder()` / `JSONEncoder()` read and write them. Times are Unix seconds
// as numbers, never `Date`, for the same reason as the Live Activity's payload: one format on
// both sides, no date strategies to agree on. Each type has `Date` helpers for the views.

/// A Lockin account: yours, from `/auth/apple`, `GET /me` and `PATCH /me`.
public struct User: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Nil until the person picks one: a new account goes to the handle picker first.
    public var handle: String?
    public var displayName: String?
    public var avatarCode: String
    public var coins: Int
    public var plusUntil: Double?
    public var createdAt: Double

    public init(
        id: String,
        handle: String?,
        displayName: String?,
        avatarCode: String,
        coins: Int = 0,
        plusUntil: Double? = nil,
        createdAt: Double
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatarCode = avatarCode
        self.coins = coins
        self.plusUntil = plusUntil
        self.createdAt = createdAt
    }

    public var avatar: AvatarCode {
        AvatarCode(avatarCode)
    }

    public var createdDate: Date {
        UnixTime.date(createdAt)
    }

    public var plusUntilDate: Date? {
        plusUntil.map(UnixTime.date)
    }
}

/// Someone you're friends with, or someone you've blocked (`GET /blocks` uses the same shape).
public struct Friend: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Optional in the type, though the server only ever sends people who've picked one: an old
    /// app must never fail to show a whole list over one odd row.
    public var handle: String?
    public var displayName: String?
    public var avatarCode: String
    /// When you became friends (or, for a block, when you blocked them).
    public var since: Double

    public init(id: String, handle: String?, displayName: String?, avatarCode: String, since: Double) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatarCode = avatarCode
        self.since = since
    }

    public var avatar: AvatarCode {
        AvatarCode(avatarCode)
    }

    /// What to call them: their display name, else their handle.
    public var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let handle, !handle.isEmpty { return handle }
        return "Friend"
    }

    public var sinceDate: Date {
        UnixTime.date(since)
    }
}

/// Your friend code: 8 characters, valid for 7 days, and the invite link that carries it.
public struct FriendCode: Codable, Hashable, Sendable {
    public var code: String
    /// `https://<invite host>/j/<code>`: opens the app when it's installed, the landing page when
    /// it isn't.
    public var url: URL
    public var expiresAt: Double

    public init(code: String, url: URL, expiresAt: Double) {
        self.code = code
        self.url = url
        self.expiresAt = expiresAt
    }

    public var expiryDate: Date {
        UnixTime.date(expiresAt)
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        now >= expiryDate
    }
}

/// `GET /handles/:handle`.
public struct HandleAvailability: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case taken
        case invalid
        case notAllowed = "not_allowed"
    }

    public var available: Bool
    public var reason: Reason?

    public init(available: Bool, reason: Reason? = nil) {
        self.available = available
        self.reason = reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decode(Bool.self, forKey: .available)
        // A reason a newer server added reads as no reason, not as a failed request.
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)).flatMap(Reason.init(rawValue:))
    }
}

/// What signing in returns to the app. The session token stays inside the client.
public struct SignInResult: Hashable, Sendable {
    public var user: User
    /// The account was made by this sign-in.
    public var isNew: Bool

    public init(user: User, isNew: Bool) {
        self.user = user
        self.isNew = isNew
    }
}

/// Why someone is being reported (`POST /reports`).
public enum ReportReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case name
    case spam
    case harassment
    case other

    public var id: String { rawValue }
}

// MARK: - Request bodies

/// `POST /auth/apple`.
public struct AppleSignInRequest: Codable, Hashable, Sendable {
    public var identityToken: String
    public var authorizationCode: String?
    /// Apple's given name, sent only on the first sign-in (Apple shares it once).
    public var displayName: String?

    public init(identityToken: String, authorizationCode: String? = nil, displayName: String? = nil) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.displayName = displayName
    }
}

/// `PATCH /me`: only the fields that are set are sent.
public struct ProfileUpdate: Codable, Hashable, Sendable {
    public var handle: String?
    public var displayName: String?
    public var avatarCode: String?

    public init(handle: String? = nil, displayName: String? = nil, avatarCode: String? = nil) {
        self.handle = handle
        self.displayName = displayName
        self.avatarCode = avatarCode
    }

    public var isEmpty: Bool {
        handle == nil && displayName == nil && avatarCode == nil
    }
}

/// `POST /devices`: where to push, and what this phone allows.
public struct DeviceRegistration: Codable, Hashable, Sendable {
    /// The APNs device token as lowercase hex.
    public var apnsToken: String
    /// The APNs host the token belongs to: Xcode builds get sandbox tokens, TestFlight and the
    /// App Store production ones.
    public var env: APNsEnvironment
    /// ActivityKit's push-to-start token, as hex (M4).
    public var pushToStartToken: String?
    /// Live Activities are switched on for Lockin in Settings.
    public var laEnabled: Bool
    /// "More frequent updates" is on in Settings.
    public var frequentPushes: Bool
    /// IANA time zone, for quiet hours and the Monday reset.
    public var tz: String

    public init(
        apnsToken: String,
        env: APNsEnvironment,
        pushToStartToken: String? = nil,
        laEnabled: Bool,
        frequentPushes: Bool,
        tz: String
    ) {
        self.apnsToken = apnsToken
        self.env = env
        self.pushToStartToken = pushToStartToken
        self.laEnabled = laEnabled
        self.frequentPushes = frequentPushes
        self.tz = tz
    }
}

/// `POST /blocks`.
public struct BlockRequest: Codable, Hashable, Sendable {
    public var userId: String

    public init(userId: String) {
        self.userId = userId
    }
}

/// `POST /reports`.
public struct ReportRequest: Codable, Hashable, Sendable {
    public var userId: String
    public var reason: ReportReason
    public var note: String?

    public init(userId: String, reason: ReportReason, note: String? = nil) {
        self.userId = userId
        self.reason = reason
        self.note = note
    }
}

// MARK: - Response envelopes

struct SignInResponse: Decodable {
    var token: String
    var user: User
    var isNew: Bool
}

struct UserEnvelope: Decodable {
    var user: User
}

struct FriendsEnvelope: Decodable {
    var friends: [Friend]
}

struct FriendEnvelope: Decodable {
    var friend: Friend
}

struct BlockedEnvelope: Decodable {
    var blocked: [Friend]
}

/// Every error response: `{ "error": "<sentence for people>", "code": "<machine code>" }`.
struct ErrorBody: Decodable {
    var error: String?
    var code: String?
}

// MARK: - Time

/// Unix seconds, the API's only time format.
public enum UnixTime {
    public static func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    public static func seconds(_ date: Date) -> Double {
        date.timeIntervalSince1970
    }
}
