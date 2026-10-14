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
    /// Days in a row the squad has focused (M5). All zeros from a server older than M5.
    public var streak: SquadStreak
    /// The IANA time zone the squad's days and its Monday follow (M5); nil from an older server.
    public var tz: String?

    public init(
        id: String,
        name: String,
        ownerId: String?,
        members: [SquadMember],
        openSessionId: String? = nil,
        muted: Bool = false,
        pet: SquadPet = SquadPet(),
        streak: SquadStreak = SquadStreak(),
        tz: String? = nil
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.members = members
        self.openSessionId = openSessionId
        self.muted = muted
        self.pet = pet
        self.streak = streak
        self.tz = tz
    }

    /// M5's fields (`pet.mood`, `pet.progress`, `streak`, `tz`) may be missing, from a server that
    /// predates them: they read as their defaults rather than failing the whole list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ownerId = try container.decodeIfPresent(String.self, forKey: .ownerId)
        members = try container.decode([SquadMember].self, forKey: .members)
        openSessionId = try container.decodeIfPresent(String.self, forKey: .openSessionId)
        muted = try container.decode(Bool.self, forKey: .muted)
        pet = try container.decodeIfPresent(SquadPet.self, forKey: .pet) ?? SquadPet()
        streak = (try? container.decodeIfPresent(SquadStreak.self, forKey: .streak)) ?? SquadStreak()
        tz = try? container.decodeIfPresent(String.self, forKey: .tz)
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

/// The squad's pet (docs/milestones/M5.md): an egg (stage 0) until two members finish a session in
/// the same room, then a baby, a teen, an adult and the prestige forms.
public struct SquadPet: Codable, Hashable, Sendable {
    /// Picked when the squad was made, so the egg is tinted with what's inside it. The app names it
    /// only once the egg hatches. Nil from a server older than M5.
    public var species: String?
    /// 0 egg, 1 baby, 2 teen, 3 adult, 4 and up prestige.
    public var stage: Int
    /// The squad's focused minutes.
    public var xp: Int
    /// 0 sad, 1 hungry, 2 content, 3 happy (`PetMood`), for today in the squad's time zone.
    public var mood: Int
    /// Towards the next stage, 0–1: 0 for an egg, 1 at the last stage (`PetRules.progress`).
    public var progress: Double

    /// - Parameters:
    ///   - mood: content unless said, as an older server's pet reads.
    ///   - progress: worked out from `xp` and `stage` unless said.
    public init(species: String? = nil, stage: Int = 0, xp: Int = 0, mood: Int = PetMood.content.rawValue, progress: Double? = nil) {
        self.species = species
        self.stage = stage
        self.xp = xp
        self.mood = mood
        self.progress = progress ?? PetRules.progress(xp: xp, stage: stage)
    }

    /// `mood` and `progress` arrived with M5: missing (an older server), the pet is content and its
    /// progress comes from its XP, as `init` has it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let species = try container.decodeIfPresent(String.self, forKey: .species)
        let stage = try container.decode(Int.self, forKey: .stage)
        let xp = try container.decode(Int.self, forKey: .xp)
        let mood: Int? = try? container.decodeIfPresent(Int.self, forKey: .mood)
        let progress: Double? = try? container.decodeIfPresent(Double.self, forKey: .progress)
        self.init(species: species, stage: stage, xp: xp, mood: mood ?? PetMood.content.rawValue, progress: progress)
    }

    /// Out of its egg: stage 1 or later.
    public var hasHatched: Bool {
        stage >= 1
    }

    /// Species and stage as `PetView` draws them, read leniently like a pushed `Pet.k`: a species
    /// this version doesn't know (or none, from an older server) draws as the default.
    public var code: PetCode {
        PetCode("\(species ?? PetCode.defaultSpecies).\(max(0, stage))")
    }

    /// `mood` held to 0–3.
    public var petMood: PetMood {
        PetMood(level: mood)
    }

    /// `progress` held to 0–1.
    public var clampedProgress: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    /// XP still to go to the next stage; nil for an egg (it hatches on a finish, not on XP) and at
    /// the last stage.
    public var xpToNextStage: Int? {
        guard hasHatched, stage < PetRules.lastStage, stage + 1 < PetRules.stageXp.count else { return nil }
        return max(0, PetRules.stageXp[stage + 1] - xp)
    }
}

/// A squad's streak (docs/milestones/M5.md): a day counts when at least half the squad (rounded
/// up) finished a session of 20 focused minutes or more, in the squad's time zone.
public struct SquadStreak: Codable, Hashable, Sendable {
    /// Days in a row; 0 once broken.
    public var count: Int
    /// Today counts already.
    public var countedToday: Bool
    /// Members who finished a 20-minute session today.
    public var doneToday: Int
    /// How many have to for today to count: half the squad, rounded up, at least 1.
    public var needed: Int

    public init(count: Int = 0, countedToday: Bool = false, doneToday: Int = 0, needed: Int = 1) {
        self.count = count
        self.countedToday = countedToday
        self.doneToday = doneToday
        self.needed = needed
    }

    /// Each field on its own, so one odd value never costs the squad.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        countedToday = (try? container.decodeIfPresent(Bool.self, forKey: .countedToday)) ?? false
        doneToday = (try? container.decodeIfPresent(Int.self, forKey: .doneToday)) ?? 0
        needed = (try? container.decodeIfPresent(Int.self, forKey: .needed)) ?? 1
    }
}

// MARK: - Leaderboard

/// A squad's week (`GET /squads/:id/leaderboard`, docs/milestones/M5.md): every member's focused
/// minutes and finished sessions from Monday 00:00 to the next Monday in the squad's time zone,
/// most minutes first. Solo sessions count too.
public struct Leaderboard: Codable, Hashable, Sendable {
    /// The Monday, "YYYY-MM-DD".
    public var weekStart: String
    /// Unix seconds: Monday 00:00 in the squad's zone.
    public var startsAt: Double
    /// Unix seconds: the next Monday 00:00 (not included).
    public var endsAt: Double
    /// Every current member, 0s included, most minutes first; ties by name.
    public var entries: [Entry]

    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var userId: String
        /// Whole focused minutes from every timer that stopped in the week.
        public var minutes: Int
        /// Sessions finished in the week.
        public var sessions: Int

        public init(userId: String, minutes: Int, sessions: Int) {
            self.userId = userId
            self.minutes = minutes
            self.sessions = sessions
        }

        public var id: String { userId }
    }

    public init(weekStart: String, startsAt: Double, endsAt: Double, entries: [Entry]) {
        self.weekStart = weekStart
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.entries = entries
    }

    public var startDate: Date {
        UnixTime.date(startsAt)
    }

    public var endDate: Date {
        UnixTime.date(endsAt)
    }

    public func entry(for userId: String) -> Entry? {
        entries.first { $0.userId == userId }
    }

    /// The squad's minutes this week, everyone's together.
    public var totalMinutes: Int {
        entries.reduce(0) { $0 + max(0, $1.minutes) }
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
    /// Only when the request carried `pushToStart` (the M4 spike): whether the server push-started
    /// the Live Activity. False when APNs refused it or it couldn't be built: the app starts the
    /// activity itself then, next time it's in the foreground.
    public var pushedToStart: Bool?

    public init(
        session: SessionInfo,
        attributes: LockinAttributes,
        contentState: LockinAttributes.ContentState,
        pushedToStart: Bool? = nil
    ) {
        self.session = session
        self.attributes = attributes
        self.contentState = contentState
        self.pushedToStart = pushedToStart
    }
}

/// The push-to-start spike's addition to `POST /sessions` and `POST /sessions/:id/join`
/// (docs/milestones/M4.md): after joining, the server starts the Live Activity on this token by
/// push, and says whether it could (`JoinedSession.pushedToStart`).
public struct PushToStart: Codable, Hashable, Sendable {
    /// ActivityKit's push-to-start token, as hex.
    public var token: String
    /// The APNs host the token belongs to.
    public var env: APNsEnvironment

    public init(token: String, env: APNsEnvironment) {
        self.token = token
        self.env = env
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

/// `PATCH /squads/:id`.
struct SquadNameRequest: Encodable, Sendable {
    var name: String
}

/// `POST /squads`. `tz` (M5) is left out when nil: the server falls back to the creator's phone's
/// zone, then UTC.
struct CreateSquadRequest: Encodable, Sendable {
    var name: String
    var tz: String?
}

/// `PATCH /squads/:id/members/me`.
struct SquadMuteRequest: Encodable, Sendable {
    var muted: Bool
}

/// `POST /sessions`. `squadId` is left out for a solo session, `pushToStart` unless the spike
/// sends one.
struct StartSessionRequest: Encodable, Sendable {
    var squadId: String?
    var minutes: Int
    var pushToStart: PushToStart?
}

/// `POST /sessions/:id/join`.
struct JoinSessionRequest: Encodable, Sendable {
    var minutes: Int
    var pushToStart: PushToStart?
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
