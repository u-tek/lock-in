import Foundation

/// The container shared by the app and the widget extension: my member id, cached squad info and
/// what the widgets draw.
public enum AppGroup {
    public enum Directory: String, CaseIterable, Sendable {
        /// The GRDB database: sessions, history and cached social data (M1).
        case database = "Database"
        /// Small files the widgets and the Live Activity read, written by the app.
        case widget = "Widget"

        /// Whether the directory stays out of device backups.
        ///
        /// The database is kept: until accounts arrive (M2), a solo user's history and coins exist
        /// only on this phone. Widget data is rebuilt by the app on every launch.
        public var isExcludedFromBackup: Bool {
            switch self {
            case .database: false
            case .widget: true
            }
        }
    }

    /// Root of the shared container.
    ///
    /// Falls back to Application Support when the App Group entitlement is missing (an unsigned
    /// simulator build), so the app still runs; the widget extension won't see the data then.
    public static func containerURL(configuration: AppConfiguration = .main) -> URL {
        let fileManager = FileManager.default
        if let identifier = identifier(configuration: configuration),
           let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        Log.app.error("App Group container unavailable; using Application Support. Widgets won't see shared data.")
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Defaults shared by the app and the widget extension (standard defaults without the App
    /// Group). Optional like `UserDefaults(suiteName:)`, though the fallback means it is never nil.
    public static func defaults(configuration: AppConfiguration = .main) -> UserDefaults? {
        identifier(configuration: configuration).flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The App Group this build was actually granted.
    ///
    /// The configured group comes from the bundle id (`group.<bundle id>`). When the group
    /// registered in the developer portal is named differently and Local.xcconfig wasn't updated
    /// to match, the group named in the embedded provisioning profile is used instead, so a
    /// development build still shares data with its widgets.
    public static func identifier(configuration: AppConfiguration = .main) -> String? {
        let fileManager = FileManager.default
        if let configured = configuration.appGroupIdentifier,
           fileManager.containerURL(forSecurityApplicationGroupIdentifier: configured) != nil {
            return configured
        }
        let granted = ProvisioningProfile.embedded?.applicationGroups ?? []
        return granted.first {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? configuration.appGroupIdentifier
    }

    /// Returns a directory inside the shared container, creating it if needed.
    public static func directory(_ directory: Directory, configuration: AppConfiguration = .main) throws -> URL {
        var url = containerURL(configuration: configuration)
            .appendingPathComponent(directory.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = directory.isExcludedFromBackup
        try url.setResourceValues(values)
        return url
    }
}
