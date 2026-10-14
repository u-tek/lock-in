import Foundation

/// The Lockin API, one method per route in docs/milestones/M2.md.
///
/// `APIClient` is the real one. The account and friends stores take this protocol so tests and
/// snapshots can hand them something that never touches the network.
///
/// Every method throws `APIError`, or `CancellationError` when the calling task was cancelled.
public protocol LockinAPI: Sendable {
    /// False when this build has no API host: nothing can be signed into.
    var isConfigured: Bool { get }
    /// A session token is stored. It may still turn out to be expired; the first request says.
    var hasSession: Bool { get }
    /// Forgets the session token. There's no route for it: the token simply stops being sent.
    func signOut()

    /// `POST /auth/apple`. Stores the session token it gets back.
    func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async throws -> SignInResult
    /// `GET /me`.
    func me() async throws -> User
    /// `PATCH /me`.
    func updateMe(_ update: ProfileUpdate) async throws -> User
    /// `GET /handles/:handle`.
    func handleAvailability(_ handle: String) async throws -> HandleAvailability
    /// `DELETE /me`. Forgets the session token once the server has deleted the account.
    func deleteMe() async throws
    /// `POST /devices`.
    func registerDevice(_ device: DeviceRegistration) async throws
    /// `GET /friends`.
    func friends() async throws -> [Friend]
    /// `POST /friends/code`: the current code, or a new one when it has expired.
    func friendCode() async throws -> FriendCode
    /// `POST /friends/redeem/:code`.
    func redeemFriendCode(_ code: String) async throws -> Friend
    /// `DELETE /friends/:id`.
    func removeFriend(id: String) async throws
    /// `GET /blocks`.
    func blocked() async throws -> [Friend]
    /// `POST /blocks`. Also ends the friendship.
    func block(userId: String) async throws
    /// `DELETE /blocks/:userId`.
    func unblock(userId: String) async throws
    /// `POST /reports`.
    func report(userId: String, reason: ReportReason, note: String?) async throws
}
