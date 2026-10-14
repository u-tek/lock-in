// DeepFocus: Lockin Plus's app blocking (SPEC.md §5.8, docs/milestones/M8.md).
//
// The person picks distracting apps with the Family Controls picker, and `DeepFocusSelection`
// keeps the choice. During a session those apps are shielded: a named ManagedSettings store holds
// the shields, and a DeviceActivity schedule ends with the session, so the monitor extension lifts
// them even when Lockin isn't running. "Open anyway" on a shield records a `Slip` in the App Group
// and lets that app through for five minutes; the app sends slips to the server when it next runs.
//
// Who calls what:
// - The app: `DeepFocusAuthorization` (Screen Time access, or "waiting on Apple"),
//   `DeepFocusSelection` (the picker's choice), `DeepFocusController` (start, pause, resume and
//   stop with the session; slips), and `ShieldIcon.storeAvatar(_:)` (the Lockling on the shield).
// - The three extensions in DeepFocusExtensions/: each hands its callback to `DeepFocusEngine`.
//
// What they share lives in the App Group's DeepFocus directory (`DeepFocusStorage`): the selection,
// the state (which session, until when, which apps are on a grace) and the slip inbox. The app
// writes the session; any process brings the shields in line with it (`DeepFocusEngine.sync`), so
// whichever runs next puts things right, and a missed callback can't leave shields up for good.
//
// Linked by the app and the three extensions, so it stays extension-safe: no UIApplication and no
// network. The shield configuration extension's sandbox forbids network requests outright
// (ShieldConfigurationDataSource docs); the other two are assumed to have none either (SPEC.md §9.3).

import DeviceActivity
import Foundation
import ManagedSettings
import os

extension ManagedSettingsStore.Name {
    /// Deep Focus's shields, shared by the app and its extensions.
    ///
    /// One store on purpose. Stores combine with the most restrictive setting winning, so a second
    /// store can't lift an app this one shields; "Open anyway" edits this store instead.
    public static let lockin = Self("lockin")
}

extension DeviceActivityName {
    /// Runs from the start of a session (or its resumption) to its end.
    public static let lockinSession = Self("lockinSession")
    /// Ends when the first "Open anyway" grace runs out, so the app is shielded again.
    public static let lockinGrace = Self("lockinGrace")
}

/// The two DeviceActivity schedules Deep Focus runs.
enum DeepFocusActivity: String, CaseIterable, Sendable {
    case session
    case grace

    var name: DeviceActivityName {
        switch self {
        case .session: .lockinSession
        case .grace: .lockinGrace
        }
    }

    init?(_ name: DeviceActivityName) {
        guard let activity = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = activity
    }
}

/// Deep Focus's log. Counts, states and session ids only: never app names or tokens.
let deepFocusLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lockin", category: "deepFocus")
