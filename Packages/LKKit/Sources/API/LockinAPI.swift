import Core
import Foundation
import Model

/// The Lockin API, one method per route in docs/milestones/M2.md and M3.md.
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
    /// Forgets the session token on this phone, without asking the server (`signOutSession()`
    /// asks it to forget the token too).
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
    /// `DELETE /auth/session`: the server forgets this session's token, then this phone does.
    func signOutSession() async throws

    // MARK: Squads (M3)

    /// `GET /squads`, in the order you joined them.
    func squads() async throws -> [Squad]
    /// `POST /squads`. 402 `plus_required` (`plusLimit` "squads") past the free limit.
    func createSquad(name: String) async throws -> Squad
    /// `PATCH /squads/:id`: the owner only.
    func renameSquad(id: String, name: String) async throws -> Squad
    /// `POST /squads/:id/invite`: your current code for the squad, or a new one once it expires.
    func squadInvite(id: String) async throws -> FriendCode
    /// `POST /squads/join/:code`. A friend code answers 422 `friend_code`.
    func joinSquad(code: String) async throws -> Squad
    /// `PATCH /squads/:id/members/me`.
    func setSquadMuted(id: String, muted: Bool) async throws -> Squad
    /// `DELETE /squads/:id/members/me`. An owner leaving hands the squad on.
    func leaveSquad(id: String) async throws

    // MARK: Sessions (M3)

    /// `POST /sessions`: solo without a squad; with one, joins its open room or opens one.
    func startSession(squadId: String?, minutes: Int) async throws -> JoinedSession
    /// `POST /sessions/:id/join`.
    func joinSession(id: String, minutes: Int) async throws -> JoinedSession
    /// `POST /sessions/:id/la-token`: the Live Activity's push token, as hex, and its APNs host.
    func uploadLiveActivityToken(sessionId: String, token: String, env: APNsEnvironment) async throws
    /// `POST /sessions/:id/pause`: the room's state afterwards.
    func pauseSession(id: String) async throws -> LockinAttributes.ContentState
    /// `POST /sessions/:id/resume`.
    func resumeSession(id: String) async throws -> LockinAttributes.ContentState
    /// `POST /sessions/:id/end`: done if the time is up, otherwise left early.
    func endSession(id: String) async throws -> LockinAttributes.ContentState
    /// `POST /sessions/:id/slip` (Deep Focus, M8).
    func slipSession(id: String) async throws -> LockinAttributes.ContentState
    /// `POST /sessions/:id/cheer`. `kind` is 0–7; 429 `cheer_too_soon` carries `retryAfter`.
    func cheer(sessionId: String, to memberId: String, kind: Int) async throws
    /// `GET /sessions/:id`. `contentState` is nil once an ended room has been cleared away.
    func session(id: String) async throws -> (session: SessionInfo, contentState: LockinAttributes.ContentState?)
    /// `GET /sessions/:id/live`: the room's state on connecting and after every change, over a
    /// WebSocket that pings every 30 seconds. The stream finishes after an "ended" state or when
    /// the connection closes (throwing `APIError` unless it closed normally); stopping iterating
    /// closes the connection.
    func liveUpdates(sessionId: String) -> AsyncThrowingStream<LiveMessage, any Error>
}
