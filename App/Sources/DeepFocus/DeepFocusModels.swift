import Combine
import Core
import DeepFocus
import FamilyControls
import Foundation

/// Deep Focus as the app holds it (docs/milestones/M8.md): Screen Time access, the shields that
/// follow the session, the chosen apps, and whether the person wants them blocked at all.
///
/// `DeepFocusCoordinator` drives the controller from the session; Settings › Deep Focus shows and
/// changes the rest.
@MainActor
final class DeepFocusModels: ObservableObject {
    /// App Group defaults key: whether to block the chosen apps during sessions.
    static let isOnDefaultsKey = "LKDeepFocusOn"

    let authorization: DeepFocusAuthorization
    let controller: DeepFocusController
    let selection: DeepFocusSelection

    /// "Block apps during sessions". Off until the person turns it on. Saved as it changes.
    @Published var isOn: Bool {
        didSet {
            if isOn != oldValue {
                defaults?.set(isOn, forKey: Self.isOnDefaultsKey)
            }
        }
    }

    /// Counts of what's chosen, for the "Choose apps" row.
    @Published private(set) var summary: DeepFocusSelection.Summary

    /// Nil for previews, which save nothing.
    private let defaults: UserDefaults?

    /// The real thing: Screen Time, ManagedSettings and DeviceActivity, on the App Group. In a
    /// build without the Family Controls entitlement none of them are touched
    /// (`DeepFocusAuthorization.Status.notEntitled`).
    convenience init() {
        let defaults = AppGroup.defaults()
        let selection = DeepFocusSelection()
        self.init(
            authorization: DeepFocusAuthorization(),
            controller: DeepFocusController(),
            selection: selection,
            defaults: defaults,
            isOn: defaults?.bool(forKey: Self.isOnDefaultsKey) ?? false,
            summary: selection.summary
        )
    }

    private init(
        authorization: DeepFocusAuthorization,
        controller: DeepFocusController,
        selection: DeepFocusSelection,
        defaults: UserDefaults?,
        isOn: Bool,
        summary: DeepFocusSelection.Summary
    ) {
        self.authorization = authorization
        self.controller = controller
        self.selection = selection
        self.defaults = defaults
        self.isOn = isOn
        self.summary = summary
    }

    /// A fixed state for snapshots and previews: never touches Screen Time, the App Group or
    /// the shields. Its files live in a temporary directory of its own.
    static func preview(
        status: DeepFocusAuthorization.Status,
        isOn: Bool = false,
        summary: DeepFocusSelection.Summary = DeepFocusSelection.Summary(applications: 0, categories: 0, webDomains: 0)
    ) -> DeepFocusModels {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepFocusModelsPreview-\(UUID().uuidString)", isDirectory: true)
        return DeepFocusModels(
            authorization: .preview(status),
            controller: .preview(),
            selection: DeepFocusSelection(storage: DeepFocusStorage(directory: directory)),
            defaults: nil,
            isOn: isOn,
            summary: summary
        )
    }

    /// Keeps the picker's choice, shows its counts, and shields it at once if a session is
    /// running.
    func save(_ newSelection: FamilyActivitySelection) {
        do {
            try selection.save(newSelection)
        } catch {
            Log.app.error("Couldn't save the Deep Focus apps")
            return
        }
        summary = DeepFocusSelection.Summary(newSelection)
        controller.selectionDidChange()
    }
}

extension DeepFocusSelection.Summary {
    /// "3 apps, 1 category", "1 website", or "None chosen".
    var text: String {
        var parts: [String] = []
        if applications > 0 {
            parts.append(applications == 1 ? "1 app" : "\(applications) apps")
        }
        if categories > 0 {
            parts.append(categories == 1 ? "1 category" : "\(categories) categories")
        }
        if webDomains > 0 {
            parts.append(webDomains == 1 ? "1 website" : "\(webDomains) websites")
        }
        return parts.isEmpty ? "None chosen" : parts.joined(separator: ", ")
    }
}
