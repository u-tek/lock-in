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
    /// `POST /squads`, in the IANA time zone `tz` (M5: the squad's days and Monday follow it; nil
    /// leaves it to the server). 402 `plus_required` (`plusLimit` "squads") past the free limit.
    func createSquad(name: String, tz: String?) async throws -> Squad
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
    /// `GET /squads/:id/leaderboard?week=YYYY-MM-DD` (M5): the week holding `week` (any day of
    /// it), or this week in the squad's time zone when nil. 403 `not_member`, 422 `week_invalid`.
    func squadLeaderboard(id: String, week: String?) async throws -> Leaderboard

    // MARK: Coins and the shop (M5)

    /// `GET /shop`: everything for sale. Needs no sign-in.
    func shop() async throws -> [ShopItem]
    /// `POST /shop/buy`: the balance after paying, and every item id you may now wear. 402
    /// `not_enough_coins`, 402 `plus_required` (a Plus item without Plus), 409 `already_owned`,
    /// 404 `item_not_found`.
    func buy(itemId: String) async throws -> (coins: Int, owned: [String])
    /// `GET /me/cosmetics`: every item id you may wear beyond the defaults, Plus items included
    /// while Plus lasts.
    func cosmetics() async throws -> [String]
    /// `POST /me/coins/import`: this phone's signed-out coins and items, once per account. 409
    /// `already_imported` the second time.
    func importCoins(coins: Int, owned: [String]) async throws -> (user: User, owned: [String])

    // MARK: Sessions (M3)

    /// `POST /sessions`: solo without a squad; with one, joins its open room or opens one. With
    /// `pushToStart` (the M4 spike), the server also starts the Live Activity on that token by
    /// push and says so in `pushedToStart`.
    func startSession(squadId: String?, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession
    /// `POST /sessions/:id/join`, with `pushToStart` as for `startSession`.
    func joinSession(id: String, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession
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

extension LockinAPI {
    /// `POST /sessions`, without push-to-start.
    public func startSession(squadId: String?, minutes: Int) async throws -> JoinedSession {
        try await startSession(squadId: squadId, minutes: minutes, pushToStart: nil)
    }

    /// `POST /sessions/:id/join`, without push-to-start.
    public func joinSession(id: String, minutes: Int) async throws -> JoinedSession {
        try await joinSession(id: id, minutes: minutes, pushToStart: nil)
    }
}
