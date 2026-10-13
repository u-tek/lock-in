#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
import Foundation

/// Why a Live Activity couldn't start, in the terms the app's prompts need.
public enum LiveActivityError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    /// Live Activities are switched off for the app in Settings. The app explains and links to
    /// Settings (CLAUDE.md, "Live Activity rules").
    case disabled
    /// This device or build can't show them: no Live Activity support, or the app isn't
    /// entitled (`NSSupportsLiveActivities` missing from Info.plist).
    case unsupported
    /// The app wasn't in the foreground. Only a `LiveActivityIntent` (M1) or a push-to-start
    /// push (M4 spike) may start one from the background.
    case notInForeground
    /// The app's own limit or the device's limit on running activities was reached. Ending
    /// orphans on launch keeps the app's own count at one.
    case tooMany
    /// Attributes and content-state over the payload budget (3.5 KB of the system's 4 KB).
    case tooLarge
    /// Anything else, with the system's description for the log and the spike screen.
    case failed(String)

    public var description: String {
        switch self {
        case .disabled: return "Live Activities are turned off for this app in Settings."
        case .unsupported: return "This device or build can't show Live Activities."
        case .notInForeground: return "Live Activities can only start while the app is open."
        case .tooMany: return "Too many Live Activities are already running."
        case .tooLarge: return "The Live Activity's data is over the 3.5 KB budget."
        case .failed(let reason): return "The Live Activity couldn't start: \(reason)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

#if canImport(ActivityKit) && os(iOS)
extension LiveActivityError {
    /// Sorts whatever `Activity.request` threw. Our own errors pass through unchanged.
    public init(_ error: Error) {
        if let error = error as? LiveActivityError {
            self = error
            return
        }
        guard let error = error as? ActivityAuthorizationError else {
            self = .failed(String(describing: error))
            return
        }
        switch error {
        case .denied:
            self = .disabled
        case .unentitled, .unsupported:
            self = .unsupported
        case .visibility:
            self = .notInForeground
        case .globalMaximumExceeded, .targetMaximumExceeded:
            self = .tooMany
        case .attributesTooLarge:
            self = .tooLarge
        default:
            // Persistence, process and identifier failures: nothing the user can act on.
            self = .failed(String(describing: error))
        }
    }
}
#endif
