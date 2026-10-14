import API
import Core
import Foundation
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
        /// Errors by route name ("me", "friends", "redeem", …), thrown every time until removed.
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

    /// A cache of its own for one test.
    static func cache() -> UserDefaults {
        let name = "lockin.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
