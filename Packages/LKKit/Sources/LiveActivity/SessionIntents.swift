import AppIntents
import Core
import Foundation

// The Live Activity's buttons: Pause, Resume and End for a solo session (M1). Cheer and the
// squad's buttons follow in M2. And Start (M6): the "Lock in" widget's button and the Control
// Center control, which start a solo session without opening the app.
//
// A `LiveActivityIntent` runs in the app's process, even when the button is in the widget
// extension's view: the system launches the app in the background if it isn't running, performs
// the intent there, and the app updates the activity. Both targets link this module, so both
// know the types; only the app ever performs them. Each one hands its command to
// `SessionIntentBridge`, where the app's session engine picks it up, so this module never
// depends on the engine.
//
// Pause, Resume and End aren't discoverable: outside a running session there's nothing to pause,
// so they stay out of Shortcuts, Spotlight and Siri. Start is: "Lock in" is something to ask for.

/// Pauses the running solo session.
public struct PauseSessionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Pause Session" }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionIntentBridge.shared.send(.pause)
        return .result()
    }
}

/// Resumes the paused solo session.
public struct ResumeSessionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Resume Session" }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionIntentBridge.shared.send(.resume)
        return .result()
    }
}

/// Ends the solo session early. The session engine records what was focused so far.
public struct EndSessionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "End Session" }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionIntentBridge.shared.send(.end)
        return .result()
    }
}

/// Starts a solo session (25 minutes unless asked otherwise) with its Live Activity, from the
/// "Lock in" widget, the Control Center control, or Shortcuts (docs/milestones/M6.md).
///
/// A `LiveActivityIntent`, so iOS performs it in the app's process, launching the app in the
/// background if it has to, and ActivityKit lets it start the activity from there. If a session is
/// already running or paused, solo or squad, it does nothing: the widget then shows that session.
public struct StartSessionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Lock In" }
    public static var description: IntentDescription {
        IntentDescription("Starts a solo focus session with its Live Activity, without opening Lockin.")
    }

    /// The session's length. The session engine holds it to 1–240 minutes.
    @Parameter(title: "Minutes", default: 25)
    public var minutes: Int

    public init() {}

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Lock in for \(\.$minutes) minutes")
    }

    public func perform() async throws -> some IntentResult {
        await SessionIntentBridge.shared.send(.start(minutes: minutes))
        return .result()
    }
}

/// Where the intents hand their commands to the app.
///
/// The app sets `handler` while it launches (before its first scene), because that's all the
/// system waits for before performing an intent in a background launch. A command that arrives
/// with no handler is dropped rather than kept: replayed on some later launch it would pause or
/// end a session the person has long since moved on from.
@MainActor
public final class SessionIntentBridge {
    public static let shared = SessionIntentBridge()

    public enum Command: Equatable, Sendable {
        case pause, resume, end
        /// A solo session of this many minutes, unless one is already going.
        case start(minutes: Int)
    }

    /// Runs a command. Return once the activity shows the change: the system may suspend the
    /// app as soon as the intent finishes.
    public var handler: ((Command) async -> Void)?

    init() {}

    func send(_ command: Command) async {
        guard let handler else {
            Log.liveActivity.error("Dropped a \(String(describing: command), privacy: .public) button press: no handler is set")
            return
        }
        await handler(command)
    }
}

/// Lets the app and the widget extension find the intents in this package (App Intents in
/// Swift packages, iOS 18). Each target lists it in its own `AppIntentsPackage`'s
/// `includedPackages`.
public struct LiveActivityIntents: AppIntentsPackage {}
