import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Puts the shields up and takes them down: `ManagedSettingsShields` for real, a fake in tests.
protocol DeepFocusShielding {
    /// Whether the person has chosen anything to shield.
    var hasSelection: Bool { get }
    /// Shields what the person chose, except what's on a grace.
    func shield(except graces: [DeepFocusState.Grace])
    func clear()
}

/// Starts and stops DeviceActivity schedules: `DeviceActivityMonitoring` for real, a fake in tests.
protocol DeepFocusMonitoring {
    func startMonitoring(_ activity: DeepFocusActivity, during schedule: DeepFocusSchedule) throws
    /// Never called with an empty list: `DeviceActivityCenter.stopMonitoring([])` stops every
    /// activity the app has.
    func stopMonitoring(_ activities: [DeepFocusActivity])
}

/// The shields, in the ManagedSettings store named `.lockin`.
///
/// Apps are shielded by token and categories by policy, for apps and websites alike. A grace takes
/// its token out of the shielded set and, for an app or website, adds it to the category policy's
/// exceptions, so an app chosen through its category gets through too. A category can only be
/// let through whole: the shield action extension is told the category's token, not the app's.
struct ManagedSettingsShields: DeepFocusShielding {
    let selection: DeepFocusSelection

    var hasSelection: Bool {
        !selection.summary.isEmpty
    }

    func shield(except graces: [DeepFocusState.Grace]) {
        let chosen = selection.load()
        let graced = GracedTokens(graces)
        let limit = DeepFocusSelection.Summary.limit
        let applications = Set(chosen.applicationTokens.subtracting(graced.applications).prefix(limit))
        let categories = Set(chosen.categoryTokens.subtracting(graced.categories).prefix(limit))
        let webDomains = Set(chosen.webDomainTokens.subtracting(graced.webDomains).prefix(limit))
        let appExceptions = Set(graced.applications.prefix(limit))
        let webExceptions = Set(graced.webDomains.prefix(limit))

        let store = ManagedSettingsStore(named: .lockin)
        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy<Application>.specific(categories, except: appExceptions)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy<WebDomain>.specific(categories, except: webExceptions)
    }

    func clear() {
        ManagedSettingsStore(named: .lockin).clearAllSettings()
    }
}

/// The tokens on a grace, decoded from the JSON the shield action extension saved. One that no
/// longer decodes is skipped, which shields it again: the safe way to be wrong.
struct GracedTokens {
    var applications: Set<ApplicationToken> = []
    var categories: Set<ActivityCategoryToken> = []
    var webDomains: Set<WebDomainToken> = []

    init(_ graces: [DeepFocusState.Grace]) {
        let decoder = JSONDecoder()
        for grace in graces {
            switch grace.target {
            case .application:
                if let token = try? decoder.decode(ApplicationToken.self, from: grace.token) {
                    applications.insert(token)
                }
            case .category:
                if let token = try? decoder.decode(ActivityCategoryToken.self, from: grace.token) {
                    categories.insert(token)
                }
            case .webDomain:
                if let token = try? decoder.decode(WebDomainToken.self, from: grace.token) {
                    webDomains.insert(token)
                }
            }
        }
    }
}

/// DeviceActivityCenter, with schedules written as times of day in `Calendar.current`.
struct DeviceActivityMonitoring: DeepFocusMonitoring {
    func startMonitoring(_ activity: DeepFocusActivity, during schedule: DeepFocusSchedule) throws {
        let parts = schedule.components(in: .current)
        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: parts.start,
            intervalEnd: parts.end,
            repeats: false
        )
        try DeviceActivityCenter().startMonitoring(activity.name, during: deviceSchedule)
    }

    func stopMonitoring(_ activities: [DeepFocusActivity]) {
        guard !activities.isEmpty else { return }
        DeviceActivityCenter().stopMonitoring(activities.map(\.name))
    }
}

/// Nothing at all, for snapshots and SwiftUI previews.
struct InertShields: DeepFocusShielding {
    var hasSelection: Bool { true }
    func shield(except graces: [DeepFocusState.Grace]) {}
    func clear() {}
}

struct InertMonitoring: DeepFocusMonitoring {
    func startMonitoring(_ activity: DeepFocusActivity, during schedule: DeepFocusSchedule) throws {}
    func stopMonitoring(_ activities: [DeepFocusActivity]) {}
}
