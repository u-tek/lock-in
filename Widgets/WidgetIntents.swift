import AppIntents
import LiveActivity

/// The Live Activity's Pause, Resume and End buttons are App Intents defined in the LiveActivity
/// package. Listing its package here lets the extension's App Intents metadata include them, so
/// the system knows what a button in the activity performs. The intents themselves run in the
/// app, which lists the same package.
struct LockinWidgetsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [LiveActivityIntents.self]
    }
}
