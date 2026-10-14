import Foundation

/// Everything the app ever reports (SPEC.md §5.6). Pushes per room are counted by the server.
public enum AnalyticsEvent: String, CaseIterable, Sendable {
    // Onboarding
    case onboardingStarted = "onboarding.started"
    case creaturePicked = "onboarding.creaturePicked"
    case notificationsAllowed = "notifications.allowed"
    case notificationsDeclined = "notifications.declined"

    // Sessions
    /// Once per install, alongside the first `sessionCompleted`.
    case firstSessionCompleted = "session.firstCompleted"
    /// Counts: `minutes`, `members` (1 when solo).
    case sessionCompleted = "session.completed"

    // Live Activity
    case liveActivityStarted = "liveActivity.started"
    case liveActivityFailed = "liveActivity.failed"
    /// Live Activities are switched off in Settings, so the island stays empty.
    case liveActivitiesDisabled = "liveActivity.disabled"

    // Squads
    case squadCreated = "squad.created"
    case inviteShared = "invite.shared"
    case inviteRedeemed = "invite.redeemed"
    case squadSessionJoined = "squad.sessionJoined"

    // "Is locking in" alerts (M4)
    /// Join 25 or Join 50 on the alert. Counts: `minutes`.
    case notificationJoin = "notifications.join"
    /// The alert itself tapped: Home opens with the squad picked.
    case notificationOpened = "notifications.opened"
    /// The push-to-start spike: a join from the background whose Live Activity the server started
    /// by push.
    case pushToStartJoin = "notifications.pushToStartJoin"

    // Retention: D1/D7/D30 are worked out from the days this arrives on.
    case appOpened = "app.opened"

    // Money
    case paywallShown = "paywall.shown"
    case trialStarted = "purchase.trialStarted"
    case purchaseCompleted = "purchase.completed"
}

/// The name of a count sent with an event.
///
/// Only a string literal can become one (the literal type is `StaticString`), so a display name,
/// squad name or id can't be passed in as a key by accident.
public struct AnalyticsKey: Hashable, Sendable, ExpressibleByStringLiteral {
    public let name: String

    public init(stringLiteral value: StaticString) {
        name = value.description
    }

    public init(extendedGraphemeClusterLiteral value: StaticString) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: StaticString) {
        self.init(stringLiteral: value)
    }
}

/// Privacy-first analytics: event counts only.
///
/// Parameters are integers under literal names by construction, so names, ids and anything people
/// typed have no way to reach the analytics service. There's no vendor yet: the app picks a sink,
/// and a vendor's SDK becomes one more sink when it's chosen.
public struct Analytics: Sendable {
    public typealias Sink = @Sendable (_ name: String, _ parameters: [String: String]) -> Void

    private let sink: Sink

    public init(sink: @escaping Sink) {
        self.sink = sink
    }

    public func track(_ event: AnalyticsEvent, counts: [AnalyticsKey: Int] = [:]) {
        var parameters: [String: String] = [:]
        for (key, count) in counts {
            parameters[key.name] = String(count)
        }
        sink(event.rawValue, parameters)
    }

    public static let disabled = Analytics { _, _ in }

    /// Writes each event to the unified log, for debug builds and the Developer menu.
    public static let debugLog = Analytics { name, parameters in
        let counts = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        Log.app.debug("Analytics \(name, privacy: .public) \(counts, privacy: .public)")
    }
}
