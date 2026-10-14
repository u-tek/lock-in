import Core
import Foundation

/// The push-to-start spike (SPEC.md §4.5 step 3, docs/spikes/push-to-start.md): the developer
/// switch "Join without opening", the push-to-start token it sends with a join, and how the last
/// try went.
///
/// All three live in the App Group's defaults. A background launch from a notification button
/// runs no screen, so the token has to be there before ActivityKit hands it over again.
public enum JoinWithoutOpening {
    /// The switch, off by default.
    public static let enabledKey = "LKJoinWithoutOpening"
    /// The latest push-to-start token, as hex.
    public static let tokenKey = "LKPushToStartToken"
    /// The last background join (`Attempt`), for the Developer menu.
    public static let lastAttemptKey = "LKPushToStartLastAttempt"

    public static func isEnabled(defaults: UserDefaults? = AppGroup.defaults()) -> Bool {
        (defaults ?? .standard).bool(forKey: enabledKey)
    }

    public static func setEnabled(_ isEnabled: Bool, defaults: UserDefaults? = AppGroup.defaults()) {
        (defaults ?? .standard).set(isEnabled, forKey: enabledKey)
    }

    /// The push-to-start token saved last, if any.
    public static func savedToken(defaults: UserDefaults? = AppGroup.defaults()) -> String? {
        guard let token = (defaults ?? .standard).string(forKey: tokenKey), !token.isEmpty else { return nil }
        return token
    }

    /// Saves the push-to-start token. Call with every one ActivityKit issues: they change.
    public static func save(token: String, defaults: UserDefaults? = AppGroup.defaults()) {
        (defaults ?? .standard).set(token, forKey: tokenKey)
    }

    /// One background join: how it ended and how long it took.
    public struct Attempt: Codable, Hashable, Sendable {
        public enum Outcome: String, Codable, Sendable {
            /// The server push-started the Live Activity (`pushedToStart: true`).
            case pushedToStart
            /// Joined, but the server couldn't push-start it: the app starts it when next opened.
            case notPushed
            /// The join itself failed.
            case failed
            /// Still waiting for the server when the time for a background action ran out.
            case timedOut
        }

        public var outcome: Outcome
        /// When it ended, Unix seconds.
        public var at: Double
        /// From the tap to the outcome.
        public var seconds: Double

        public init(outcome: Outcome, at: Double, seconds: Double) {
            self.outcome = outcome
            self.at = at
            self.seconds = seconds
        }
    }

    public static func lastAttempt(defaults: UserDefaults? = AppGroup.defaults()) -> Attempt? {
        guard let data = (defaults ?? .standard).data(forKey: lastAttemptKey) else { return nil }
        return try? JSONDecoder().decode(Attempt.self, from: data)
    }

    public static func record(_ attempt: Attempt, defaults: UserDefaults? = AppGroup.defaults()) {
        guard let data = try? JSONEncoder().encode(attempt) else { return }
        (defaults ?? .standard).set(data, forKey: lastAttemptKey)
    }
}
