import Foundation

/// Identifiers and service settings injected at build time through Info.plist.
///
/// The values come from `Config/Shared.xcconfig` (and `Config/Local.xcconfig` when present), via
/// the `LK*` keys in `project.yml`. An xcconfig variable that is left unset expands to an empty
/// string, so empty and whitespace-only values read as `nil`.
public struct AppConfiguration: Sendable, Equatable {
    public var appGroupIdentifier: String?
    /// Host of the API Worker deployed from /server. The xcconfig holds only the host, because
    /// "//" starts a comment there. Nil means no backend: the app runs solo only.
    public var apiHost: String?
    /// The APNs environment this build was configured for (`LK_APNS_ENV`). Prefer
    /// `APNsEnvironment.current`, which checks the provisioning profile first.
    public var apnsEnvironment: APNsEnvironment?
    /// Shows the Developer menu (APNs spike, Live Activity Lab). On until launch, because the
    /// owner tests TestFlight builds and can't run debug builds from Xcode.
    public var developerToolsEnabled: Bool

    public init(
        appGroupIdentifier: String? = nil,
        apiHost: String? = nil,
        apnsEnvironment: APNsEnvironment? = nil,
        developerToolsEnabled: Bool = false
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.apiHost = apiHost
        self.apnsEnvironment = apnsEnvironment
        self.developerToolsEnabled = developerToolsEnabled
    }

    /// `https://<apiHost>`, or nil without a host.
    ///
    /// A full URL is accepted too (the `https:/$()/host` xcconfig trick, or a value typed straight
    /// into Info.plist), and trailing slashes are dropped so paths can be appended cleanly.
    public var apiBaseURL: URL? {
        guard var host = apiHost else { return nil }
        while host.hasSuffix("/") {
            host.removeLast()
        }
        guard !host.isEmpty else { return nil }
        return host.contains("://") ? URL(string: host) : URL(string: "https://\(host)")
    }

    public init(infoDictionary: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = infoDictionary[key] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func flag(_ key: String) -> Bool {
            // A plist edited by hand may hold a real boolean rather than the xcconfig's "YES".
            if let bool = infoDictionary[key] as? Bool {
                return bool
            }
            return value(key).map { ["yes", "true", "1"].contains($0.lowercased()) } ?? false
        }
        self.init(
            appGroupIdentifier: value(InfoKey.appGroup),
            apiHost: value(InfoKey.apiHost),
            apnsEnvironment: value(InfoKey.apnsEnvironment).flatMap { APNsEnvironment(parsing: $0) },
            developerToolsEnabled: flag(InfoKey.developerTools)
        )
    }

    /// The configuration of the running app or extension.
    public static let main = AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])

    /// The Info.plist keys, as written by `project.yml`. The widget extension only has the App
    /// Group.
    public enum InfoKey {
        public static let appGroup = "LKAppGroupIdentifier"
        public static let apiHost = "LKAPIHost"
        public static let apnsEnvironment = "LKAPNsEnvironment"
        public static let developerTools = "LKDeveloperTools"
    }
}
