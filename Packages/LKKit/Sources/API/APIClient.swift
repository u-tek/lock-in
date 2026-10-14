import Core
import Foundation
import Model

/// The Lockin API over HTTPS, as JSON (docs/milestones/M2.md, M3.md), and the live view of a
/// session over a WebSocket (APIClient+Live.swift).
///
/// A plain value: it holds nothing that changes except the token, which lives in its
/// `TokenStore`. Every request except sign-in carries `Authorization: Bearer <token>`. A 401 on an
/// authenticated request clears the token, so the next look at `hasSession` says signed out.
public struct APIClient: LockinAPI {
    /// `https://<LK_API_HOST>`, or nil when the build has none.
    public let baseURL: URL?
    let tokens: any TokenStore
    let session: URLSession

    public init(
        baseURL: URL? = AppConfiguration.main.apiBaseURL,
        tokens: any TokenStore = KeychainTokenStore(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
    }

    public var isConfigured: Bool {
        baseURL != nil
    }

    public var hasSession: Bool {
        tokens.load() != nil
    }

    public func signOut() {
        tokens.clear()
    }

    // MARK: - Account

    public func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async throws -> SignInResult {
        let body = AppleSignInRequest(identityToken: identityToken, authorizationCode: authorizationCode, displayName: displayName)
        let response = try await send(.post, ["auth", "apple"], body: body, authenticated: false, as: SignInResponse.self)
        tokens.save(response.token)
        return SignInResult(user: response.user, isNew: response.isNew)
    }

    public func me() async throws -> User {
        try await send(.get, ["me"], as: UserEnvelope.self).user
    }

    public func updateMe(_ update: ProfileUpdate) async throws -> User {
        try await send(.patch, ["me"], body: update, as: UserEnvelope.self).user
    }

    public func handleAvailability(_ handle: String) async throws -> HandleAvailability {
        try await send(.get, ["handles", handle], as: HandleAvailability.self)
    }

    public func deleteMe() async throws {
        try await send(.delete, ["me"])
        tokens.clear()
    }

    public func registerDevice(_ device: DeviceRegistration) async throws {
        try await send(.post, ["devices"], body: device)
    }

    // MARK: - Friends

    public func friends() async throws -> [Friend] {
        try await send(.get, ["friends"], as: FriendsEnvelope.self).friends
    }

    public func friendCode() async throws -> FriendCode {
        try await send(.post, ["friends", "code"], as: FriendCode.self)
    }

    public func redeemFriendCode(_ code: String) async throws -> Friend {
        try await send(.post, ["friends", "redeem", code], as: FriendEnvelope.self).friend
    }

    public func removeFriend(id: String) async throws {
        try await send(.delete, ["friends", id])
    }

    public func blocked() async throws -> [Friend] {
        try await send(.get, ["blocks"], as: BlockedEnvelope.self).blocked
    }

    public func block(userId: String) async throws {
        try await send(.post, ["blocks"], body: BlockRequest(userId: userId))
    }

    public func unblock(userId: String) async throws {
        try await send(.delete, ["blocks", userId])
    }

    public func report(userId: String, reason: ReportReason, note: String?) async throws {
        try await send(.post, ["reports"], body: ReportRequest(userId: userId, reason: reason, note: note))
    }

    // MARK: - Signing out

    public func signOutSession() async throws {
        let sent = tokens.load()
        try await send(.delete, ["auth", "session"])
        // Unless a new sign-in has stored another token meanwhile.
        if tokens.load() == sent {
            tokens.clear()
        }
    }

    // MARK: - Squads

    public func squads() async throws -> [Squad] {
        try await send(.get, ["squads"], as: SquadsEnvelope.self).squads
    }

    public func createSquad(name: String) async throws -> Squad {
        try await send(.post, ["squads"], body: SquadNameRequest(name: name), as: SquadEnvelope.self).squad
    }

    public func renameSquad(id: String, name: String) async throws -> Squad {
        try await send(.patch, ["squads", id], body: SquadNameRequest(name: name), as: SquadEnvelope.self).squad
    }

    public func squadInvite(id: String) async throws -> FriendCode {
        try await send(.post, ["squads", id, "invite"], as: FriendCode.self)
    }

    public func joinSquad(code: String) async throws -> Squad {
        try await send(.post, ["squads", "join", code], as: SquadEnvelope.self).squad
    }

    public func setSquadMuted(id: String, muted: Bool) async throws -> Squad {
        try await send(.patch, ["squads", id, "members", "me"], body: SquadMuteRequest(muted: muted), as: SquadEnvelope.self).squad
    }

    public func leaveSquad(id: String) async throws {
        try await send(.delete, ["squads", id, "members", "me"])
    }

    // MARK: - Sessions

    public func startSession(squadId: String?, minutes: Int) async throws -> JoinedSession {
        try await send(.post, ["sessions"], body: StartSessionRequest(squadId: squadId, minutes: minutes), as: JoinedSession.self)
    }

    public func joinSession(id: String, minutes: Int) async throws -> JoinedSession {
        try await send(.post, ["sessions", id, "join"], body: JoinSessionRequest(minutes: minutes), as: JoinedSession.self)
    }

    public func uploadLiveActivityToken(sessionId: String, token: String, env: APNsEnvironment) async throws {
        try await send(.post, ["sessions", sessionId, "la-token"], body: LiveActivityTokenRequest(token: token, env: env))
    }

    public func pauseSession(id: String) async throws -> LockinAttributes.ContentState {
        try await memberAction("pause", sessionId: id)
    }

    public func resumeSession(id: String) async throws -> LockinAttributes.ContentState {
        try await memberAction("resume", sessionId: id)
    }

    public func endSession(id: String) async throws -> LockinAttributes.ContentState {
        try await memberAction("end", sessionId: id)
    }

    public func slipSession(id: String) async throws -> LockinAttributes.ContentState {
        try await memberAction("slip", sessionId: id)
    }

    public func cheer(sessionId: String, to memberId: String, kind: Int) async throws {
        try await send(.post, ["sessions", sessionId, "cheer"], body: CheerRequest(to: memberId, kind: kind))
    }

    public func session(id: String) async throws -> (session: SessionInfo, contentState: LockinAttributes.ContentState?) {
        let snapshot = try await send(.get, ["sessions", id], as: SessionSnapshot.self)
        return (snapshot.session, snapshot.contentState)
    }

    /// `POST /sessions/:id/<action>`: no body, the room's state back.
    private func memberAction(_ action: String, sessionId: String) async throws -> LockinAttributes.ContentState {
        try await send(.post, ["sessions", sessionId, action], as: ContentStateEnvelope.self).contentState
    }

    // MARK: - Plumbing

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// The request for a route. Each path part is percent-encoded on its own, so a handle or code
    /// can never add a path segment of its own.
    func request(
        _ method: Method,
        _ path: [String],
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard let baseURL else { throw APIError.notConfigured }
        var url = baseURL
        for part in path {
            url = url.appending(component: part, directoryHint: .notDirectory)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            // No token, no point asking: the answer would be a 401.
            guard let token = tokens.load() else {
                throw APIError.server(status: 401, code: .unauthorised, message: nil)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    @discardableResult
    private func send(
        _ method: Method,
        _ path: [String],
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        let urlRequest = try self.request(method, path, body: body, authenticated: authenticated)
        // Logged by the route's first part only: handles, codes and ids stay out of the log.
        let route = "\(method.rawValue) /\(path.first ?? "")"
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: urlRequest)
        } catch let error as URLError {
            guard let failure = APIError(error) else { throw CancellationError() }
            Log.api.error("\(route, privacy: .public) failed: \(error.code.rawValue, privacy: .public)")
            throw failure
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let status = http.statusCode
        guard (200..<300).contains(status) else {
            let failure = APIError(status: status, body: data)
            Log.api.info("\(route, privacy: .public) → \(status, privacy: .public) \(failure.code?.rawValue ?? "", privacy: .public)")
            if failure.isUnauthorised && authenticated {
                tokens.clear()
            }
            throw failure
        }
        Log.api.debug("\(route, privacy: .public) → \(status, privacy: .public)")
        return data
    }

    private func send<Response: Decodable>(
        _ method: Method,
        _ path: [String],
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await send(method, path, body: body, authenticated: authenticated)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            Log.api.error("\(method.rawValue, privacy: .public) /\(path.first ?? "", privacy: .public): unexpected response body")
            throw APIError.invalidResponse
        }
    }
}
