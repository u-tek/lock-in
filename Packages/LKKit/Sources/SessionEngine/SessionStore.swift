import Core
import Foundation
import Model
import os

/// Where the session engine keeps its state: a small JSON file in the App Group, or memory for
/// tests and previews.
///
/// One file holds everything (member id, avatar, the session in progress, history and coins), so
/// a write is all or nothing. GRDB arrives when history needs queries (M5).
public struct SessionStore: Sendable {
    static let fileName = "sessions.json"
    /// Where an unreadable file is moved, so a bug can be looked into without losing coins.
    static let unreadableFileName = "sessions.unreadable.json"
    /// The most recent sessions kept. Plenty for today's minutes and a long streak; full history
    /// is a Plus feature that arrives with GRDB.
    static let historyLimit = 500

    private let backend: Backend

    private init(backend: Backend) {
        self.backend = backend
    }

    /// `sessions.json` in the App Group's database directory, or in Application Support when the
    /// App Group isn't available (an unsigned simulator build).
    public static func appGroup() -> SessionStore {
        let directory: URL
        do {
            directory = try AppGroup.directory(.database)
        } catch {
            Log.session.error("Database directory unavailable; using Application Support")
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppGroup.Directory.database.rawValue, isDirectory: true)
        }
        return file(at: directory.appendingPathComponent(fileName))
    }

    /// Nothing touches the disk. Copies share the same memory, like copies of a file store share
    /// the file.
    public static func inMemory() -> SessionStore {
        SessionStore(backend: .memory(MemoryBackend()))
    }

    static func file(at url: URL) -> SessionStore {
        SessionStore(backend: .file(FileBackend(url: url)))
    }

    /// What was saved last, or nil when nothing was (a first launch).
    func load() -> StoredSessions? {
        switch backend {
        case .memory(let memory): memory.load()
        case .file(let file): file.load()
        }
    }

    func save(_ sessions: StoredSessions) {
        switch backend {
        case .memory(let memory): memory.save(sessions)
        case .file(let file): file.save(sessions)
        }
    }

    private enum Backend: Sendable {
        case memory(MemoryBackend)
        case file(FileBackend)
    }
}

/// Encoded, not just held, so tests round-trip through the same JSON as the file.
private final class MemoryBackend: Sendable {
    private let data = OSAllocatedUnfairLock<Data?>(initialState: nil)

    func load() -> StoredSessions? {
        data.withLock { $0 }.flatMap { try? JSONDecoder().decode(StoredSessions.self, from: $0) }
    }

    func save(_ sessions: StoredSessions) {
        guard let encoded = try? JSONEncoder().encode(sessions) else { return }
        data.withLock { $0 = encoded }
    }
}

private final class FileBackend: Sendable {
    let url: URL
    /// Set when the file exists but couldn't be read. Saving then would replace someone's coins
    /// and history with an empty start, so nothing is written until the next launch.
    private let writesBlocked = OSAllocatedUnfairLock(initialState: false)

    init(url: URL) {
        self.url = url
    }

    func load() -> StoredSessions? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Most likely data protection: the phone hasn't been unlocked since it restarted.
            writesBlocked.withLock { $0 = true }
            Log.session.error("Session file exists but couldn't be read; not saving this launch")
            return nil
        }
        do {
            return try JSONDecoder().decode(StoredSessions.self, from: data)
        } catch {
            let aside = url.deletingLastPathComponent().appendingPathComponent(SessionStore.unreadableFileName)
            try? fileManager.removeItem(at: aside)
            try? fileManager.moveItem(at: url, to: aside)
            Log.session.error("Session file unreadable; set aside, starting fresh")
            return nil
        }
    }

    func save(_ sessions: StoredSessions) {
        guard !writesBlocked.withLock({ $0 }) else { return }
        do {
            let data = try JSONEncoder().encode(sessions)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Readable while the phone is locked: the Live Activity's buttons run the app in the
            // background, often from the Lock Screen.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Log.session.error("Couldn't save sessions")
        }
    }
}

/// Everything the engine keeps between launches.
///
/// Decoding is lenient: a missing key reads as its default, so a file written by another version
/// of the app never costs anyone their coins.
struct StoredSessions: Codable, Equatable, Sendable {
    /// This install's member id: the `me` of the solo Live Activity. M2 replaces it with the
    /// server's id for the signed-in user.
    var memberID: String
    /// Avatar code (`AvatarCode.code`).
    var avatar: String
    var active: ActiveSession?
    /// Oldest first, at most `SessionStore.historyLimit`.
    var history: [SessionRecord]
    var coins: Int
    /// Counted apart from the history, which is capped.
    var completedSessions: Int
    /// The squad room this phone is in (M3): from joining until the room ends or this phone
    /// leaves it. It outlives `active` while squadmates are still focusing after this phone's
    /// timer is done: the room's Live Activity stays up until the room ends.
    var room: RoomLink?
    /// A squad session ended on this phone while the server couldn't be told (offline): its id,
    /// until `POST /sessions/:id/end` goes through.
    var pendingEnd: String?

    init(
        memberID: String = ShortID.make(),
        avatar: String = AvatarCode.default.code,
        active: ActiveSession? = nil,
        history: [SessionRecord] = [],
        coins: Int = 0,
        completedSessions: Int = 0,
        room: RoomLink? = nil,
        pendingEnd: String? = nil
    ) {
        self.memberID = memberID
        self.avatar = avatar
        self.active = active
        self.history = history
        self.coins = coins
        self.completedSessions = completedSessions
        self.room = room
        self.pendingEnd = pendingEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try container.decodeIfPresent(String.self, forKey: .memberID) ?? ShortID.make()
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? AvatarCode.default.code
        active = try container.decodeIfPresent(ActiveSession.self, forKey: .active)
        history = try container.decodeIfPresent([SessionRecord].self, forKey: .history) ?? []
        coins = try container.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        // A room this version can't read is only a lost live view, never lost coins.
        room = try? container.decodeIfPresent(RoomLink.self, forKey: .room)
        pendingEnd = try? container.decodeIfPresent(String.self, forKey: .pendingEnd)
    }

    /// Adds a finished session, dropping the oldest beyond the limit.
    mutating func append(_ record: SessionRecord) {
        history.append(record)
        if history.count > SessionStore.historyLimit {
            history.removeFirst(history.count - SessionStore.historyLimit)
        }
    }
}

/// The session in progress.
struct ActiveSession: Codable, Equatable, Sendable {
    /// The session's short id: the Live Activity's `sid` and the record's id.
    var id: String
    var startedAt: Date
    /// Moves later by the length of each pause.
    var endsAt: Date
    /// Set while paused.
    var pausedAt: Date?
    var plannedMinutes: Int
    /// The Live Activity's content-state version (`v`), raised with every change.
    var version: Int
    /// The ActivityKit id of this session's Live Activity, to find it again after a relaunch.
    /// Solo only: a squad timer's activity belongs to its room (`RoomLink.activityID`).
    var activityID: String?
    /// The squad room this timer runs in (`RoomLink.sessionId`); nil for a solo session. The
    /// room's server is the authority for it: `startedAt`, `endsAt` and `pausedAt` follow this
    /// phone's member in the room's state (`b`, `e`, `q`).
    var sessionId: String? = nil

    var isSquad: Bool {
        sessionId != nil
    }

    var plannedSeconds: TimeInterval {
        TimeInterval(plannedMinutes * 60)
    }

    var isPaused: Bool {
        pausedAt != nil
    }

    /// Seconds left on the timer at `date`: frozen while paused, never negative.
    func remaining(at date: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(pausedAt ?? date))
    }

    /// Seconds focused by `date`, pauses left out, within 0...planned.
    func focusedSeconds(at date: Date) -> Int {
        // The end moves by every pause, so planned minus remaining is the time on the clock. A
        // clock set back before the start would make it negative.
        let focused = plannedSeconds - endsAt.timeIntervalSince(pausedAt ?? date)
        return Int(min(max(focused, 0), plannedSeconds).rounded(.down))
    }
}

/// The squad room this phone is in (M3), as the server described it when this phone joined.
struct RoomLink: Codable, Equatable, Sendable {
    var squadId: String
    /// The room's Live Activity attributes as the server made them: `sid` is the session and `me`
    /// this phone's member id (the account's user id).
    var attributes: LockinAttributes
    /// The newest state seen, from whichever source got here first: a request's answer, the
    /// live view, or `GET /sessions/:id`.
    var state: LockinAttributes.ContentState
    /// The ActivityKit id of the room's Live Activity, to find it again after a relaunch.
    var activityID: String?

    var sessionId: String {
        attributes.sid
    }

    var me: String {
        attributes.me
    }

    /// This phone's member in `state`.
    var mine: LockinAttributes.ContentState.Member? {
        state.member(id: me)
    }
}
