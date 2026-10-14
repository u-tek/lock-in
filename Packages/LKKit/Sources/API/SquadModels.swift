import Core
import Foundation
import Model

// The JSON of squads and sessions (docs/milestones/M3.md), shaped exactly like the server's
// response builders: `squadView` in server/src/squads.ts, and `sessionView` / `joined` /
// `stateMessage` in server/src/room.ts. Same rules as Models.swift: camelCase keys, Unix seconds
// as numbers, nulls read as nil.

// MARK: - Squads

/// A squad you're in: `GET /squads`, and the answer of every route that changes one.
public struct Squad: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Null only for a moment while an owner's account is being deleted.
    public var ownerId: String?
    /// Longest-standing first (by `joinedAt`).
    public var members: [SquadMember]
    /// The squad's room while someone's locked in: starting a session with this squad joins it.
    public var openSessionId: String?
    /// Your own mute switch for "X is locking in" (M4). Each member has their own.
    public var muted: Bool
    public var pet: SquadPet

    public init(
        id: String,
        name: String,
        ownerId: String?,
        members: [SquadMember],
        openSessionId: String? = nil,
        muted: Bool = false,
        pet: SquadPet = SquadPet()
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.members = members
        self.openSessionId = openSessionId
        self.muted = muted
        self.pet = pet
    }

    /// Someone is locked in with the squad right now.
    public var isLive: Bool {
        openSessionId != nil
    }

    public func isOwned(by userId: String?) -> Bool {
        userId != nil && ownerId == userId
    }

    public func member(id: String) -> SquadMember? {
        members.first { $0.id == id }
    }
}

/// A member of a squad, as the squad lists them.
public struct SquadMember: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var handle: String?
    public var displayName: String?
    public var avatarCode: String
    /// When they joined the squad, Unix seconds.
    public var joinedAt: Double

    public init(id: String, handle: String?, displayName: String?, avatarCode: String, joinedAt: Double) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatarCode = avatarCode
        self.joinedAt = joinedAt
    }

    /// What to call them: their display name, else their handle, else "Lockling" (what the Live
    /// Activity calls them too).
    public var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let handle, !handle.isEmpty { return handle }
        return "Lockling"
    }

    public var avatar: AvatarCode {
        AvatarCode(avatarCode)
    }

    public var joinedDate: Date {
        UnixTime.date(joinedAt)
    }
}

/// The squad's pet. `species` stays nil until the egg hatches (M5).
public struct SquadPet: Codable, Hashable, Sendable {
    public var species: String?
    public var stage: Int
    public var xp: Int

    public init(species: String? = nil, stage: Int = 0, xp: Int = 0) {
        self.species = species
        self.stage = stage
        self.xp = xp
    }

    public var hasHatched: Bool {
        species != nil
    }
}

// MARK: - Sessions

/// A session (a room): `Session` in docs/milestones/M3.md.
public struct SessionInfo: Codable, Hashable, Sendable, Identifiable {
    public static let open = "open"
    public static let ended = "ended"

    public var id: String
    /// Nil for a solo session.
    public var squadId: String?
    /// Who opened the room. Empty in the rare answer where the host's account has since been
    /// deleted (the server sends null then).
    public var hostId: String
    /// "open" or "ended".
    public var status: String
    public var createdAt: Double

    public init(id: String, squadId: String?, hostId: String, status: String, createdAt: Double) {
        self.id = id
        self.squadId = squadId
        self.hostId = hostId
        self.status = status
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        squadId = try container.decodeIfPresent(String.self, forKey: .squadId)
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId) ?? ""
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(Double.self, forKey: .createdAt)
    }

    public var isEnded: Bool {
        status == Self.ended
    }

    public var createdDate: Date {
        UnixTime.date(createdAt)
    }
}

/// What starting or joining a session returns: everything ActivityKit needs to start the Live
/// Activity (`Joined` in docs/milestones/M3.md). `attributes.me` is the caller's member id.
public struct JoinedSession: Codable, Hashable, Sendable {
    public var session: SessionInfo
    public var attributes: LockinAttributes
    public var contentState: LockinAttributes.ContentState

    public init(session: SessionInfo, attributes: LockinAttributes, contentState: LockinAttributes.ContentState) {
        self.session = session
        self.attributes = attributes
        self.contentState = contentState
    }
}

/// One message of a session's live view (`GET /sessions/:id/live`, a WebSocket).
public enum LiveMessage: Hashable, Sendable {
    /// The room's state: on connecting, and right after every change. `status` is "open" or
    /// "ended"; the room closes the socket after "ended".
    case state(status: String, contentState: LockinAttributes.ContentState?)
    /// The room's answer to the app's ping.
    case pong

    /// What the app sends to keep the connection warm: `{"type":"ping"}`.
    public static let ping = #"{"type":"ping"}"#

    /// Reads one message. Nil for anything this build doesn't know (a type a newer server added,
    /// or something that isn't the contract's JSON), which the live view skips.
    public init?(json data: Data) {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        switch wire.type {
        case "state":
            guard let status = wire.status else { return nil }
            self = .state(status: status, contentState: wire.contentState)
        case "pong":
            self = .pong
        default:
            return nil
        }
    }

    /// The same, from a text frame.
    public init?(text: String) {
        self.init(json: Data(text.utf8))
    }

    /// The room has ended: nothing more will come.
    public var isEnded: Bool {
        if case .state(let status, _) = self {
            return status == SessionInfo.ended
        }
        return false
    }

    private struct Wire: Decodable {
        var type: String
        var status: String?
        var contentState: LockinAttributes.ContentState?
    }
}

// MARK: - Request bodies

/// `POST /squads`, `PATCH /squads/:id`.
struct SquadNameRequest: Encodable, Sendable {
    var name: String
}

/// `PATCH /squads/:id/members/me`.
struct SquadMuteRequest: Encodable, Sendable {
    var muted: Bool
}

/// `POST /sessions`. `squadId` is left out for a solo session.
struct StartSessionRequest: Encodable, Sendable {
    var squadId: String?
    var minutes: Int
}

/// `POST /sessions/:id/join`.
struct JoinSessionRequest: Encodable, Sendable {
    var minutes: Int
}

/// `POST /sessions/:id/la-token`.
struct LiveActivityTokenRequest: Encodable, Sendable {
    var token: String
    var env: APNsEnvironment
}

/// `POST /sessions/:id/cheer`.
struct CheerRequest: Encodable, Sendable {
    var to: String
    var kind: Int
}

// MARK: - Response envelopes

struct SquadsEnvelope: Decodable {
    var squads: [Squad]
}

struct SquadEnvelope: Decodable {
    var squad: Squad
}

struct ContentStateEnvelope: Decodable {
    var contentState: LockinAttributes.ContentState
}

/// `GET /sessions/:id`: `contentState` is null once an ended room has been cleared away.
struct SessionSnapshot: Decodable {
    var session: SessionInfo
    var contentState: LockinAttributes.ContentState?
}
