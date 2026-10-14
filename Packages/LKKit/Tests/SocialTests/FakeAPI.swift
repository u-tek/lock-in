import API
import Core
import Foundation
import Model
@testable import Social

/// A Lockin API that answers from fixed values and records every call, for the store tests. It
/// clears its token on a 401 and stores one on sign-in, as `APIClient` does.
final class FakeAPI: LockinAPI, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case signIn(identityToken: String, displayName: String?)
        case me
        case updateMe(ProfileUpdate)
        case handle(String)
        case deleteMe
        case registerDevice(DeviceRegistration)
        case friends
        case friendCode
        case redeem(String)
        case removeFriend(String)
        case blocked
        case block(String)
        case unblock(String)
        case report(String, ReportReason, String?)
        case signOutSession
        case squads
        case createSquad(String)
        case renameSquad(String, String)
        case squadInvite(String)
        case joinSquad(String)
        case setSquadMuted(String, Bool)
        case leaveSquad(String)
    }

    /// What the fake answers with. Change it with `set(_:)`.
    struct Answers {
        var token: String?
        var user = TestData.ava
        var isNew = false
        var friends: [Friend] = []
        var code = TestData.code
        var blocked: [Friend] = []
        var redeems = TestData.noor
        var availability = HandleAvailability(available: true)
        var squads: [Squad] = []
        /// What `POST /squads/join/:code` joins.
        var joins = TestData.goblins
        var squadCode = TestData.squadCode
        /// Errors by route name ("me", "friends", "redeem", "joinSquad", …), thrown every time
        /// until removed.
        var failures: [String: APIError] = [:]
    }

    let isConfigured: Bool
    private let lock = NSLock()
    private var answers: Answers
    private var recorded: [Call] = []

    init(isConfigured: Bool = true, token: String? = nil, _ configure: (inout Answers) -> Void = { _ in }) {
        self.isConfigured = isConfigured
        var answers = Answers()
        answers.token = token
        configure(&answers)
        self.answers = answers
    }

    func set(_ change: (inout Answers) -> Void) {
        lock.withLock { change(&answers) }
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    var token: String? {
        lock.withLock { answers.token }
    }

    var hasSession: Bool {
        token != nil
    }

    func signOut() {
        lock.withLock { answers.token = nil }
    }

    func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async throws -> SignInResult {
        try answer(.signIn(identityToken: identityToken, displayName: displayName), route: "signIn", authenticated: false) { answers in
            answers.token = "t0k3n"
            return SignInResult(user: answers.user, isNew: answers.isNew)
        }
    }

    func me() async throws -> User {
        try answer(.me, route: "me") { $0.user }
    }

    func updateMe(_ update: ProfileUpdate) async throws -> User {
        try answer(.updateMe(update), route: "updateMe") { answers in
            if let handle = update.handle { answers.user.handle = handle }
            if let name = update.displayName { answers.user.displayName = name }
            if let avatar = update.avatarCode { answers.user.avatarCode = avatar }
            return answers.user
        }
    }

    func handleAvailability(_ handle: String) async throws -> HandleAvailability {
        try answer(.handle(handle), route: "handle") { $0.availability }
    }

    func deleteMe() async throws {
        try answer(.deleteMe, route: "deleteMe") { answers in
            answers.token = nil
        }
    }

    func registerDevice(_ device: DeviceRegistration) async throws {
        try answer(.registerDevice(device), route: "registerDevice") { _ in }
    }

    func friends() async throws -> [Friend] {
        try answer(.friends, route: "friends") { $0.friends }
    }

    func friendCode() async throws -> FriendCode {
        try answer(.friendCode, route: "friendCode") { $0.code }
    }

    func redeemFriendCode(_ code: String) async throws -> Friend {
        try answer(.redeem(code), route: "redeem") { $0.redeems }
    }

    func removeFriend(id: String) async throws {
        try answer(.removeFriend(id), route: "removeFriend") { _ in }
    }

    func blocked() async throws -> [Friend] {
        try answer(.blocked, route: "blocked") { $0.blocked }
    }

    func block(userId: String) async throws {
        try answer(.block(userId), route: "block") { _ in }
    }

    func unblock(userId: String) async throws {
        try answer(.unblock(userId), route: "unblock") { _ in }
    }

    func report(userId: String, reason: ReportReason, note: String?) async throws {
        try answer(.report(userId, reason, note), route: "report") { _ in }
    }

    func signOutSession() async throws {
        try answer(.signOutSession, route: "signOutSession") { answers in
            answers.token = nil
        }
    }

    // MARK: Squads

    func squads() async throws -> [Squad] {
        try answer(.squads, route: "squads") { $0.squads }
    }

    func createSquad(name: String) async throws -> Squad {
        try answer(.createSquad(name), route: "createSquad") { answers in
            let squad = Squad(
                id: "SqNew00001",
                name: name,
                ownerId: answers.user.id,
                members: [SquadMember(id: answers.user.id, handle: answers.user.handle, displayName: answers.user.displayName, avatarCode: answers.user.avatarCode, joinedAt: 1_791_900_000)]
            )
            answers.squads.append(squad)
            return squad
        }
    }

    func renameSquad(id: String, name: String) async throws -> Squad {
        try answer(.renameSquad(id, name), route: "renameSquad") { answers in
            guard let index = answers.squads.firstIndex(where: { $0.id == id }) else { return TestData.goblins }
            answers.squads[index].name = name
            return answers.squads[index]
        }
    }

    func squadInvite(id: String) async throws -> FriendCode {
        try answer(.squadInvite(id), route: "squadInvite") { $0.squadCode }
    }

    func joinSquad(code: String) async throws -> Squad {
        try answer(.joinSquad(code), route: "joinSquad") { answers in
            answers.squads.append(answers.joins)
            return answers.joins
        }
    }

    func setSquadMuted(id: String, muted: Bool) async throws -> Squad {
        try answer(.setSquadMuted(id, muted), route: "setSquadMuted") { answers in
            guard let index = answers.squads.firstIndex(where: { $0.id == id }) else { return TestData.goblins }
            answers.squads[index].muted = muted
            return answers.squads[index]
        }
    }

    func leaveSquad(id: String) async throws {
        try answer(.leaveSquad(id), route: "leaveSquad") { answers in
            answers.squads.removeAll { $0.id == id }
        }
    }

    // MARK: Sessions: the session engine's tests cover these.

    func startSession(squadId: String?, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession {
        throw APIError.notConfigured
    }

    func joinSession(id: String, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession {
        throw APIError.notConfigured
    }

    func uploadLiveActivityToken(sessionId: String, token: String, env: APNsEnvironment) async throws {
        throw APIError.notConfigured
    }

    func pauseSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    func resumeSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    func endSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    func slipSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    func cheer(sessionId: String, to memberId: String, kind: Int) async throws {
        throw APIError.notConfigured
    }

    func session(id: String) async throws -> (session: SessionInfo, contentState: LockinAttributes.ContentState?) {
        throw APIError.notConfigured
    }

    func liveUpdates(sessionId: String) -> AsyncThrowingStream<LiveMessage, any Error> {
        AsyncThrowingStream { $0.finish(throwing: APIError.notConfigured) }
    }

    private func answer<Value>(
        _ call: Call,
        route: String,
        authenticated: Bool = true,
        _ respond: (inout Answers) -> Value
    ) throws -> Value {
        try lock.withLock {
            recorded.append(call)
            if authenticated && answers.token == nil {
                throw APIError.server(status: 401, code: .unauthorised, message: nil)
            }
            if let failure = answers.failures[route] {
                if failure.isUnauthorised && authenticated {
                    answers.token = nil
                }
                throw failure
            }
            return respond(&answers)
        }
    }
}

/// Counts analytics events by name.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    var analytics: Analytics {
        Analytics { [self] name, _ in
            lock.withLock { names.append(name) }
        }
    }

    func count(_ event: AnalyticsEvent) -> Int {
        lock.withLock { names.filter { $0 == event.rawValue }.count }
    }
}

enum TestData {
    static let ava = User(id: "uAva000001", handle: "ava", displayName: "Ava", avatarCode: "b1.c1.e1.h1", createdAt: 1_791_900_000)
    static let newcomer = User(id: "uNew000001", handle: nil, displayName: nil, avatarCode: "b0.c0.e0.h0", createdAt: 1_791_900_000)
    static let noor = Friend(id: "uNoor00001", handle: "noor.k", displayName: "Noor", avatarCode: "b2.c4.e2.h0", since: 1_791_800_000)
    static let kai = Friend(id: "uKai000001", handle: "kai", displayName: "Kai", avatarCode: "b0.c7.e3.h2", since: 1_791_700_000)
    static let bea = Friend(id: "uBea000001", handle: "bea", displayName: "bea", avatarCode: "b0.c0.e0.h0", since: 1_791_600_000)
    static let code = FriendCode(code: "AVA2CDEF", url: URL(string: "https://lockin.example/j/AVA2CDEF")!, expiresAt: 1_792_500_000)
    static let device = DeviceRegistration(apnsToken: "a1b2c3", env: .sandbox, laEnabled: true, frequentPushes: false, tz: "Australia/Sydney")

    static let goblins = Squad(
        id: "SqGoblins1",
        name: "Library Goblins",
        ownerId: noor.id,
        members: [
            SquadMember(id: noor.id, handle: "noor.k", displayName: "Noor", avatarCode: "b2.c4.e2.h0", joinedAt: 1_791_800_000),
            SquadMember(id: ava.id, handle: "ava", displayName: "Ava", avatarCode: "b1.c1.e1.h1", joinedAt: 1_791_900_000),
        ]
    )
    static let owls = Squad(
        id: "SqOwls0001",
        name: "Night Owls",
        ownerId: ava.id,
        members: [SquadMember(id: ava.id, handle: "ava", displayName: "Ava", avatarCode: "b1.c1.e1.h1", joinedAt: 1_791_700_000)],
        openSessionId: "RmOwls0001",
        muted: false,
        pet: SquadPet(species: "fox", stage: 1, xp: 120)
    )
    static let squadCode = FriendCode(code: "SQD2CDEF", url: URL(string: "https://lockin.example/j/SQD2CDEF")!, expiresAt: 1_792_500_000)

    /// A cache of its own for one test.
    static func cache() -> UserDefaults {
        let name = "lockin.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
