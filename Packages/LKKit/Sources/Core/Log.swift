import Foundation
import os

/// Unified logging categories.
///
/// Never log display names, squad names, push tokens or auth tokens: log counts, states and ids
/// only. Mark an id `privacy: .public` only when it's a short session or member id, never a token.
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Lockin"

    public static let app = Logger(subsystem: subsystem, category: "app")
    /// Starting, updating and ending activities, and their push tokens arriving (not the tokens).
    public static let liveActivity = Logger(subsystem: subsystem, category: "liveActivity")
    /// Notification permission, device tokens and incoming pushes.
    public static let push = Logger(subsystem: subsystem, category: "push")
    /// The local session timer: start, pause, resume, finish.
    public static let session = Logger(subsystem: subsystem, category: "session")
    /// Requests to the API Worker: paths, status codes and timings, never bodies.
    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
