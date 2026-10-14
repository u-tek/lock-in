import AppIntents
import LiveActivity

/// Lets the system find the Live Activity's Pause, Resume and End intents, and the Lock in
/// widget's and control's Start, which live in the LiveActivity package rather than in the app
/// target. Without it the buttons have nothing to run in the app's process. The widget extension
/// lists the same package in its own.
struct LockinAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [LiveActivityIntents.self]
    }
}
