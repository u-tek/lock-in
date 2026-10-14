import Foundation

/// What a shield covers, as the shield extensions are told: an app, a category, or a website.
public enum DeepFocusShieldTarget: String, Codable, Sendable {
    case application
    case category
    case webDomain
}

/// What the app last said about the session, and the apps let through on a grace. Kept in
/// `state.json` in the App Group, so every process sees the same thing.
///
/// Times are Unix seconds (`Double`), as everywhere the app shares state.
struct DeepFocusState: Codable, Equatable, Sendable {
    struct Session: Codable, Equatable, Sendable {
        /// The session's id: the server's for a squad session, which slips are sent against.
        var id: String
        /// When the session ends.
        var endsAt: Double
        var isPaused: Bool
        /// Changes the shield's line: "Your squad's still going." rather than "Your session's...".
        var withSquad: Bool
    }

    /// An app, category or website let through by "Open anyway" until `until`.
    struct Grace: Codable, Equatable, Sendable {
        var target: DeepFocusShieldTarget
        /// The token as JSON: opaque, compared byte for byte, decoded only to shield.
        var token: Data
        var until: Double
    }

    var session: Session?
    var graces: [Grace]
    /// When the grace timer (`DeviceActivityName.lockinGrace`) was last set to end, so syncing
    /// again doesn't reschedule it. Rescheduling an ongoing interval may end it, which calls the
    /// monitor extension, which syncs: without this, that could go round for ever.
    var graceTimerEnd: Double?

    init(session: Session? = nil, graces: [Grace] = [], graceTimerEnd: Double? = nil) {
        self.session = session
        self.graces = graces
        self.graceTimerEnd = graceTimerEnd
    }

    /// How early a schedule's callback may arrive and still count as on time. DeviceActivity
    /// schedules are written to the second and their callbacks needn't be exact: a callback that
    /// came at the end but a moment early must still read as the end, or it would put the shields
    /// back up with nothing left to take them down. The cost is shields lifting up to a minute early.
    static let tolerance: TimeInterval = 60

    /// Whether the chosen apps should be shielded now.
    func isShielding(at now: Date) -> Bool {
        guard let session, !session.isPaused else { return false }
        return now.timeIntervalSince1970 < session.endsAt - Self.tolerance
    }

    /// Drops the graces that have run out, and every grace when nothing is shielded.
    mutating func pruneGraces(at now: Date) {
        guard isShielding(at: now) else {
            graces = []
            return
        }
        graces.removeAll { $0.until <= now.timeIntervalSince1970 + Self.tolerance }
    }

    /// When the grace timer should end: when the first grace runs out.
    var nextGraceEnd: Double? {
        graces.map(\.until).min()
    }

    // Lenient decoding: a key a later version dropped, or one this version doesn't know yet,
    // mustn't lose the session.
    private enum CodingKeys: String, CodingKey {
        case session, graces, graceTimerEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decodeIfPresent(Session.self, forKey: .session)
        graces = (try? container.decodeIfPresent([Grace].self, forKey: .graces)) ?? []
        graceTimerEnd = try container.decodeIfPresent(Double.self, forKey: .graceTimerEnd)
    }
}
