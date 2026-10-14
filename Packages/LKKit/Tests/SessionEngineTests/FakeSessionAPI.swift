import API
import Core
import Foundation
import Model
@testable import SessionEngine

/// A Lockin API for the squad session tests: answers from fixed values, records every call, and
/// hands the test the live view so it can play the room's messages.
final class FakeSessionAPI: LockinAPI, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case startSession(squadId: String?, minutes: Int)
        case joinSession(String, minutes: Int)
        case uploadToken(String, token: String, env: APNsEnvironment)
        case pause(String)
        case resume(String)
        case end(String)
        case slip(String)
        case cheer(String, to: String, kind: Int)
        case session(String)
        case liveUpdates(String)
    }

    struct Answers {
        /// What `POST /sessions` answers.
        var joined = SquadData.joined()
        /// What `POST /sessions/:id/join` answers.
        var rejoined = SquadData.joined()
        /// What pause, resume, end and slip answer, by action.
        var states: [String: LockinAttributes.ContentState] = [:]
        /// What `GET /sessions/:id` answers.
        var snapshot = SessionSnapshotAnswer(session: SquadData.session(), contentState: SquadData.room(v: 1, SquadData.mine()))
        /// Errors by route ("startSession", "pause", "session", …), every time until removed.
        var failures: [String: APIError] = [:]
        /// What a start or join with a push-to-start token says about the push (M4 spike).
        var pushedToStart = true
    }

    struct SessionSnapshotAnswer {
        var session: SessionInfo
        var contentState: LockinAttributes.ContentState?
    }

    private let lock = NSLock()
    private var answers: Answers
    private var recorded: [Call] = []
    private var sentPushToStarts: [PushToStart?] = []
    private var live: [AsyncThrowingStream<LiveMessage, any Error>.Continuation] = []

    init(_ configure: (inout Answers) -> Void = { _ in }) {
        var answers = Answers()
        configure(&answers)
        self.answers = answers
    }

    func set(_ change: (inout Answers) -> Void) {
        lock.withLock { change(&answers) }
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func count(_ call: Call) -> Int {
        calls.filter { $0 == call }.count
    }

    /// Live views opened so far.
    var liveViews: Int {
        lock.withLock { live.count }
    }

    /// Plays a message on the newest live view.
    func send(_ message: LiveMessage) {
        let continuation = lock.withLock { live.last }
        continuation?.yield(message)
    }

    /// Drops the newest live view.
    func dropLiveView() {
        let continuation = lock.withLock { live.last }
        continuation?.finish(throwing: APIError.offline)
    }

    // MARK: - Squad sessions

    func startSession(squadId: String?, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession {
        note(pushToStart)
        return try answer(.startSession(squadId: squadId, minutes: minutes), route: "startSession") { answers in
            Self.answering(pushToStart, with: answers.joined, pushed: answers.pushedToStart)
        }
    }

    func joinSession(id: String, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession {
        note(pushToStart)
        return try answer(.joinSession(id, minutes: minutes), route: "joinSession") { answers in
            Self.answering(pushToStart, with: answers.rejoined, pushed: answers.pushedToStart)
        }
    }

    /// The push-to-start tokens sent with starts and joins, in order (nil for none).
    var pushToStarts: [PushToStart?] {
        lock.withLock { sentPushToStarts }
    }

    private func note(_ pushToStart: PushToStart?) {
        lock.withLock { sentPushToStarts.append(pushToStart) }
    }

    /// `pushedToStart` comes back only when a token went with the request, as from the server.
    private static func answering(_ pushToStart: PushToStart?, with joined: JoinedSession, pushed: Bool) -> JoinedSession {
        var answer = joined
        answer.pushedToStart = pushToStart == nil ? nil : pushed
        return answer
    }

    func uploadLiveActivityToken(sessionId: String, token: String, env: APNsEnvironment) async throws {
        try answer(.uploadToken(sessionId, token: token, env: env), route: "uploadToken") { _ in }
    }

    func pauseSession(id: String) async throws -> LockinAttributes.ContentState {
        try action(.pause(id), "pause")
    }

    func resumeSession(id: String) async throws -> LockinAttributes.ContentState {
        try action(.resume(id), "resume")
    }

    func endSession(id: String) async throws -> LockinAttributes.ContentState {
        try action(.end(id), "end")
    }

    func slipSession(id: String) async throws -> LockinAttributes.ContentState {
        try action(.slip(id), "slip")
    }

    func cheer(sessionId: String, to memberId: String, kind: Int) async throws {
        try answer(.cheer(sessionId, to: memberId, kind: kind), route: "cheer") { _ in }
    }

    func session(id: String) async throws -> (session: SessionInfo, contentState: LockinAttributes.ContentState?) {
        let snapshot = try answer(.session(id), route: "session") { $0.snapshot }
        return (snapshot.session, snapshot.contentState)
    }

    func liveUpdates(sessionId: String) -> AsyncThrowingStream<LiveMessage, any Error> {
        var captured: AsyncThrowingStream<LiveMessage, any Error>.Continuation?
        let stream = AsyncThrowingStream<LiveMessage, any Error> { continuation in
            captured = continuation
        }
        lock.withLock {
            recorded.append(.liveUpdates(sessionId))
            if let captured {
                live.append(captured)
            }
        }
        return stream
    }

    private func action(_ call: Call, _ route: String) throws -> LockinAttributes.ContentState {
        try answer(call, route: route) { answers in
            answers.states[route] ?? answers.joined.contentState
        }
    }

    private func answer<Value>(_ call: Call, route: String, _ respond: (inout Answers) -> Value) throws -> Value {
        try lock.withLock {
            recorded.append(call)
            if let failure = answers.failures[route] {
                throw failure
            }
            return respond(&answers)
        }
    }

    // MARK: - Accounts and friends: not used here

    var isConfigured: Bool { true }
    var hasSession: Bool { true }
    func signOut() {}
    func signOutSession() async throws {}

    func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async throws -> SignInResult {
        throw APIError.notConfigured
    }

    func me() async throws -> User { throw APIError.notConfigured }
    func updateMe(_ update: ProfileUpdate) async throws -> User { throw APIError.notConfigured }
    func handleAvailability(_ handle: String) async throws -> HandleAvailability { throw APIError.notConfigured }
    func deleteMe() async throws { throw APIError.notConfigured }
    func registerDevice(_ device: DeviceRegistration) async throws { throw APIError.notConfigured }
    func friends() async throws -> [Friend] { throw APIError.notConfigured }
    func friendCode() async throws -> FriendCode { throw APIError.notConfigured }
    func redeemFriendCode(_ code: String) async throws -> Friend { throw APIError.notConfigured }
    func removeFriend(id: String) async throws { throw APIError.notConfigured }
    func blocked() async throws -> [Friend] { throw APIError.notConfigured }
    func block(userId: String) async throws { throw APIError.notConfigured }
    func unblock(userId: String) async throws { throw APIError.notConfigured }
    func report(userId: String, reason: ReportReason, note: String?) async throws { throw APIError.notConfigured }
    func squads() async throws -> [Squad] { throw APIError.notConfigured }
    func createSquad(name: String, tz: String?) async throws -> Squad { throw APIError.notConfigured }
    func renameSquad(id: String, name: String) async throws -> Squad { throw APIError.notConfigured }
    func squadInvite(id: String) async throws -> FriendCode { throw APIError.notConfigured }
    func joinSquad(code: String) async throws -> Squad { throw APIError.notConfigured }
    func setSquadMuted(id: String, muted: Bool) async throws -> Squad { throw APIError.notConfigured }
    func leaveSquad(id: String) async throws { throw APIError.notConfigured }
    func squadLeaderboard(id: String, week: String?) async throws -> Leaderboard { throw APIError.notConfigured }
    func shop() async throws -> [ShopItem] { throw APIError.notConfigured }
    func buy(itemId: String) async throws -> (coins: Int, owned: [String]) { throw APIError.notConfigured }
    func cosmetics() async throws -> [String] { throw APIError.notConfigured }
    func importCoins(coins: Int, owned: [String]) async throws -> (user: User, owned: [String]) { throw APIError.notConfigured }
}

/// A squad room of two: Noor (the host, 50 minutes) and this phone's Ava, who joins at
/// `referenceDate` for 25 minutes unless a test says otherwise.
enum SquadData {
    typealias Member = LockinAttributes.ContentState.Member
    typealias State = LockinAttributes.ContentState

    static let squadId = "SqGoblins1"
    static let sessionId = "RmGoblins1"
    static let me = "uAva000001"
    static let noor = "uNoor00001"
    static let attributes = LockinAttributes(sid: sessionId, me: me, sq: "Library Goblins")

    /// This phone's member: joined at `referenceDate` for `minutes`, its end moved later by
    /// `pausedFor`.
    static func mine(
        _ state: MemberState = .focusing,
        minutes: Int = 25,
        pausedFor: TimeInterval = 0,
        pausedAt: Date? = nil
    ) -> Member {
        Member(
            id: me,
            name: "Ava",
            avatar: AvatarCode("b1.c1.e1.h1"),
            state: state,
            start: referenceDate,
            end: referenceDate.addingTimeInterval(TimeInterval(minutes * 60) + pausedFor),
            pausedAt: pausedAt
        )
    }

    static func noorMember(_ state: MemberState = .focusing) -> Member {
        Member(
            id: noor,
            name: "Noor",
            avatar: AvatarCode("b2.c4.e2.h0"),
            state: state,
            start: referenceDate.addingTimeInterval(-300),
            end: referenceDate.addingTimeInterval(50 * 60 - 300)
        )
    }

    /// The room's state: Noor first (the host), then Ava.
    static func room(v: Int, _ mine: Member, noor: Member = SquadData.noorMember()) -> State {
        State(v: v, m: [noor, mine])
    }

    static func session(status: String = SessionInfo.open, squadId: String? = SquadData.squadId) -> SessionInfo {
        SessionInfo(id: sessionId, squadId: squadId, hostId: noor, status: status, createdAt: referenceDate.timeIntervalSince1970 - 300)
    }

    static func joined(_ state: State? = nil, squadId: String? = SquadData.squadId) -> JoinedSession {
        JoinedSession(
            session: SquadData.session(squadId: squadId),
            attributes: attributes,
            contentState: state ?? SquadData.room(v: 1, SquadData.mine())
        )
    }
}

/// Lets the engine's tasks run (the live view's messages arrive on the main actor) until
/// `condition` holds, for up to about a second.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        await Task.yield()
    }
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
func makeSquadEngine(clock: TestClock, api: FakeSessionAPI?, store: SessionStore = .inMemory()) -> SessionEngine {
    let engine = SessionEngine(store: store, liveActivities: nil, api: api, now: { clock.now })
    engine.pushEnvironment = .sandbox
    return engine
}
