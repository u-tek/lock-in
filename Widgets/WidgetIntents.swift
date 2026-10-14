import AppIntents
import LiveActivity

/// The Live Activity's Pause, Resume and End buttons, and the Lock in widget's and control's Start,
/// are App Intents defined in the LiveActivity package. Listing its package here lets the
/// extension's App Intents metadata include them, so the system knows what a button in the
/// activity or a widget performs. The intents themselves run in the app, which lists the same
/// package. The Squad pet widget's settings (`SquadPetConfiguration`) live in this target.
struct LockinWidgetsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [LiveActivityIntents.self]
    }
}
