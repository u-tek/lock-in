import Foundation

/// The machine-readable `code` of an error response (docs/milestones/M2.md). The app switches on
/// these, never on the server's sentence. Codes this build doesn't know arrive as `.other`.
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
    case other(String)

    /// Every code in the contract, for tests.
    public static let known: [APIErrorCode] = [
        .unauthorised, .appleTokenInvalid, .handleTaken, .handleInvalid, .handleNotAllowed,
        .nameInvalid, .nameNotAllowed, .avatarInvalid, .deviceInvalid, .codeNotFound,
        .codeExpired, .ownCode, .alreadyFriends, .blocked, .userNotFound, .reportInvalid,
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
        case .other(let raw): raw
        }
    }
}

/// Why a request to the Lockin API didn't work.
public enum APIError: Error, Hashable, Sendable {
    /// This build has no API host (`LK_API_HOST` empty): the app runs solo.
    case notConfigured
    /// No connection: offline, the connection dropped, or it timed out.
    case offline
    /// Any other transport failure, by `URLError.Code` raw value.
    case network(code: Int)
    /// The server said no.
    case server(status: Int, code: APIErrorCode, message: String?)
    /// A success whose body wasn't what the contract promised.
    case invalidResponse

    public var code: APIErrorCode? {
        if case .server(_, let code, _) = self { code } else { nil }
    }

    public var status: Int? {
        if case .server(let status, _, _) = self { status } else { nil }
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
        self = .server(status: status, code: code, message: decoded?.error)
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
        case .server(let status, let code, let message):
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
            case .other:
                if status == 429 { return "That's a lot of tries. Please wait a moment." }
                return message ?? "Something went wrong. Please try again."
            }
        }
    }
}
