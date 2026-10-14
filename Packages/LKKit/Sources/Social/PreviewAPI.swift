import API
import Foundation

/// A Lockin API made of fixed answers: what the preview stores run on, so snapshots show the real
/// screens without a network, a Keychain or a server.
public struct PreviewAPI: LockinAPI {
    public var isConfigured: Bool
    public var user: User?
    public var friendsList: [Friend]
    public var code: FriendCode
    public var blockedList: [Friend]
    /// Who any code turns out to belong to.
    public var redeems: Friend

    public init(
        isConfigured: Bool = true,
        user: User? = PreviewAPI.sampleUser,
        friends: [Friend] = [],
        code: FriendCode = PreviewAPI.sampleCode,
        blocked: [Friend] = [],
        redeems: Friend = PreviewAPI.sampleFriend
    ) {
        self.isConfigured = isConfigured
        self.user = user
        friendsList = friends
        self.code = code
        blockedList = blocked
        self.redeems = redeems
    }

    public static let sampleUser = User(
        id: "uPreview01",
        handle: "you",
        displayName: "You",
        avatarCode: "b0.c2.e1.h1",
        coins: 120,
        createdAt: 1_791_900_000
    )

    public static let sampleCode = FriendCode(
        code: "KQ7M2XPA",
        url: URL(string: "https://lockin.example/j/KQ7M2XPA")!,
        expiresAt: 1_792_500_000
    )

    public static let sampleFriend = Friend(
        id: "uPreview02",
        handle: "ava",
        displayName: "Ava",
        avatarCode: "b1.c1.e1.h1",
        since: 1_791_900_000
    )

    public var hasSession: Bool {
        true
    }

    public func signOut() {}

    public func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async throws -> SignInResult {
        var fresh = user ?? Self.sampleUser
        fresh.handle = nil
        fresh.displayName = displayName
        return SignInResult(user: fresh, isNew: true)
    }

    public func me() async throws -> User {
        user ?? Self.sampleUser
    }

    public func updateMe(_ update: ProfileUpdate) async throws -> User {
        var updated = user ?? Self.sampleUser
        if let handle = update.handle {
            updated.handle = handle
        }
        if let displayName = update.displayName {
            updated.displayName = displayName
        }
        if let avatarCode = update.avatarCode {
            updated.avatarCode = avatarCode
        }
        return updated
    }

    public func handleAvailability(_ handle: String) async throws -> HandleAvailability {
        HandleAvailability(available: true)
    }

    public func deleteMe() async throws {}

    public func registerDevice(_ device: DeviceRegistration) async throws {}

    public func friends() async throws -> [Friend] {
        friendsList
    }

    public func friendCode() async throws -> FriendCode {
        code
    }

    public func redeemFriendCode(_ code: String) async throws -> Friend {
        redeems
    }

    public func removeFriend(id: String) async throws {}

    public func blocked() async throws -> [Friend] {
        blockedList
    }

    public func block(userId: String) async throws {}

    public func unblock(userId: String) async throws {}

    public func report(userId: String, reason: ReportReason, note: String?) async throws {}
}
