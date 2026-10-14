import Foundation

/// The machine-readable `code` of an error response (docs/milestones/M2.md, M3.md). The app
/// switches on these, never on the server's sentence. Codes this build doesn't know arrive as
/// `.other`.
public enum APIErrorCode: Hashable, Sendable {
    case unauthorised
    case appleTokenInvalid
    case handleTaken
    case handleInvalid
    case handleNotAllowed
    case nameInvalid
    case nameNotAllowed
    case avatarInvalid
    case deviceInvalid
    case codeNotFound
    case codeExpired
    case ownCode
    case alreadyFriends
    case blocked
    case userNotFound
    case reportInvalid
    // Squads and sessions (M3)
    /// 402: a free limit was reached; `APIError.plusLimit` says which ("squads" or "members").
    case plusRequired
    case notOwner
    /// 403: not in that squad (or session), or no such squad.
    case notMember
    /// 422 from `POST /squads/join/:code`: the code is a friend code, for `friends/redeem`.
    case friendCode
    case alreadyMember
    /// 409: already in an open session somewhere; `APIError.sessionId` says which.
    case alreadyInSession
    case sessionEnded
    case sessionNotFound
    case roomFull
    /// 409: the timer isn't in a state the action applies to (pausing a paused timer, …).
    case badState
    case tokenInvalid
    case cheerInvalid
    /// 429: one cheer every 10 seconds; `APIError.retryAfter` says how long to wait.
    case cheerTooSoon
    case minutesInvalid
    /// 503: the room couldn't be opened after a few tries.
    case tryAgain
    case other(String)

    /// Every code in the contract, for tests.
    public static let known: [APIErrorCode] = [
        .unauthorised, .appleTokenInvalid, .handleTaken, .handleInvalid, .handleNotAllowed,
        .nameInvalid, .nameNotAllowed, .avatarInvalid, .deviceInvalid, .codeNotFound,
        .codeExpired, .ownCode, .alreadyFriends, .blocked, .userNotFound, .reportInvalid,
        .plusRequired, .notOwner, .notMember, .friendCode, .alreadyMember, .alreadyInSession,
        .sessionEnded, .sessionNotFound, .roomFull, .badState, .tokenInvalid, .cheerInvalid,
        .cheerTooSoon, .minutesInvalid, .tryAgain,
    ]

    public init(rawValue: String) {
        self = Self.known.first { $0.rawValue == rawValue } ?? .other(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .unauthorised: "unauthorised"
        case .appleTokenInvalid: "apple_token_invalid"
        case .handleTaken: "handle_taken"
        case .handleInvalid: "handle_invalid"
        case .handleNotAllowed: "handle_not_allowed"
        case .nameInvalid: "name_invalid"
        case .nameNotAllowed: "name_not_allowed"
        case .avatarInvalid: "avatar_invalid"
        case .deviceInvalid: "device_invalid"
        case .codeNotFound: "code_not_found"
        case .codeExpired: "code_expired"
        case .ownCode: "own_code"
        case .alreadyFriends: "already_friends"
        case .blocked: "blocked"
        case .userNotFound: "user_not_found"
        case .reportInvalid: "report_invalid"
        case .plusRequired: "plus_required"
        case .notOwner: "not_owner"
        case .notMember: "not_member"
        case .friendCode: "friend_code"
        case .alreadyMember: "already_member"
        case .alreadyInSession: "already_in_session"
        case .sessionEnded: "session_ended"
        case .sessionNotFound: "session_not_found"
        case .roomFull: "room_full"
        case .badState: "bad_state"
        case .tokenInvalid: "token_invalid"
        case .cheerInvalid: "cheer_invalid"
        case .cheerTooSoon: "cheer_too_soon"
        case .minutesInvalid: "minutes_invalid"
        case .tryAgain: "try_again"
        case .other(let raw): raw
        }
    }
}

/// The extra fields a few error responses carry (docs/milestones/M3.md, "As built").
public struct APIErrorDetails: Hashable, Sendable {
    /// 402 `plus_required`: which free limit, "squads" or "members".
    public var limit: String?
    /// 409 `already_in_session`: the session the caller is already in.
    public var sessionId: String?
    /// 429: seconds to wait before trying again.
    public var retryAfter: Double?

    public init(limit: String? = nil, sessionId: String? = nil, retryAfter: Double? = nil) {
        self.limit = limit
        self.sessionId = sessionId
        self.retryAfter = retryAfter
    }

    public static let empty = APIErrorDetails()
}

/// Why a request to the Lockin API didn't work.
public enum APIError: Error, Hashable, Sendable {
    /// This build has no API host (`LK_API_HOST` empty): the app runs solo.
    case notConfigured
    /// No connection: offline, the connection dropped, or it timed out.
    case offline
    /// Any other transport failure, by `URLError.Code` raw value.
    case network(code: Int)
    /// The server said no. `details` holds the few extra fields some errors carry.
    case server(status: Int, code: APIErrorCode, message: String?, details: APIErrorDetails = .empty)
    /// A success whose body wasn't what the contract promised.
    case invalidResponse

    public var code: APIErrorCode? {
        if case .server(_, let code, _, _) = self { code } else { nil }
    }

    public var status: Int? {
        if case .server(let status, _, _, _) = self { status } else { nil }
    }

    /// The extra fields of a server error; empty for every other kind.
    public var details: APIErrorDetails {
        if case .server(_, _, _, let details) = self { details } else { .empty }
    }

    /// 402 `plus_required`: the free limit that was hit, "squads" or "members". The app opens the
    /// paywall for it (SPEC.md §2, paywall moment 2).
    public var plusLimit: String? {
        code == .plusRequired ? details.limit : nil
    }

    /// 409 `already_in_session`: the session the caller is already in.
    public var sessionId: String? {
        details.sessionId
    }

    /// 429: seconds to wait before trying again, when the server said.
    public var retryAfter: Double? {
        details.retryAfter
    }

    /// The session is gone (expired, revoked, or the account deleted elsewhere): the token has
    /// been cleared and the app should show itself signed out. A rejected Apple token on sign-in
    /// is a different 401: there was no session to lose.
    public var isUnauthorised: Bool {
        code == .unauthorised || (status == 401 && code != .appleTokenInvalid)
    }

    /// Reads a `URLError`. Nil for a cancelled request, which callers treat as cancellation.
    init?(_ error: URLError) {
        switch error.code {
        case .cancelled:
            return nil
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed:
            self = .offline
        default:
            self = .network(code: error.code.rawValue)
        }
    }

    /// An error response, from its status and body. A body without a code still says something:
    /// a 401 is always "unauthorised".
    init(status: Int, body: Data) {
        let decoded = try? JSONDecoder().decode(ErrorBody.self, from: body)
        let code: APIErrorCode
        if let raw = decoded?.code, !raw.isEmpty {
            code = APIErrorCode(rawValue: raw)
        } else if status == 401 {
            code = .unauthorised
        } else {
            code = .other("http_\(status)")
        }
        let details = APIErrorDetails(limit: decoded?.limit, sessionId: decoded?.sessionId, retryAfter: decoded?.retryAfter)
        self = .server(status: status, code: code, message: decoded?.error, details: details)
    }
}

extension APIError: LocalizedError {
    /// Short and warm, for an alert or the line under a field. The server's own sentence is the
    /// fallback for codes this build doesn't know.
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Lockin's server isn't set up yet."
        case .offline:
            return "You're offline. Check your connection and try again."
        case .network:
            return "Couldn't reach Lockin. Please try again."
        case .invalidResponse:
            return "Something went wrong. Please try again."
        case .server(let status, let code, let message, let details):
            switch code {
            case .unauthorised: return "You've been signed out. Please sign in again."
            case .appleTokenInvalid: return "Sign in with Apple didn't go through. Please try again."
            case .handleTaken: return "That username is taken."
            case .handleInvalid: return "Use 3–20 letters, numbers, _ or ., starting with a letter."
            case .handleNotAllowed, .nameNotAllowed: return "Please pick something else."
            case .nameInvalid: return "Names are 1 to 12 characters."
            case .avatarInvalid: return "That Lockling couldn't be saved."
            case .deviceInvalid: return "This iPhone couldn't be registered for notifications."
            case .codeNotFound: return "That code doesn't exist. Check it and try again."
            case .codeExpired: return "That code has expired. Ask for a new one."
            case .ownCode: return "That's your own code."
            case .alreadyFriends: return "You're already friends."
            case .blocked: return "You can't add this person."
            case .userNotFound: return "That person isn't on Lockin any more."
            case .reportInvalid: return "That report couldn't be sent."
            case .plusRequired:
                switch details.limit {
                case "squads": return "Lockin Plus lets you be in up to 3 squads."
                case "members": return "This squad is full. Lockin Plus squads hold up to 6."
                default: return message ?? "That needs Lockin Plus."
                }
            case .notOwner: return "Only the squad's owner can do that."
            case .notMember: return "You're not in this squad."
            case .friendCode: return "That's a friend code. Add your friend on the Friends screen."
            case .alreadyMember: return "You're already in this squad."
            case .alreadyInSession: return "You're already in a session. End it first."
            case .sessionEnded: return "That session has ended."
            case .sessionNotFound: return "That session isn't there any more."
            case .roomFull: return "This session is full."
            case .badState: return "Your timer has already moved on."
            case .tokenInvalid: return "The Live Activity couldn't be connected to your squad."
            case .cheerInvalid: return "That cheer couldn't be sent."
            case .cheerTooSoon: return "One cheer every 10 seconds. Try again in a moment."
            case .minutesInvalid: return "Sessions are 1 to 240 minutes."
            case .tryAgain: return "Couldn't start the session. Please try again."
            case .other:
                if status == 429 { return "That's a lot of tries. Please wait a moment." }
                return message ?? "Something went wrong. Please try again."
            }
        }
    }
}
