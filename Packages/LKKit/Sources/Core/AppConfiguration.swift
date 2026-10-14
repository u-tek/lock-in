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
    /// Host of the web pages: the privacy policy, terms and support page (`LK_WEB_HOST`, M9), e.g.
    /// the launch domain. Nil: they're on the API host, which serves them too (server/src/pages.ts).
    public var webHost: String?
    /// The APNs environment this build was configured for (`LK_APNS_ENV`). Prefer
    /// `APNsEnvironment.current`, which checks the provisioning profile first.
    public var apnsEnvironment: APNsEnvironment?
    /// Shows the Developer menu (APNs spike, Live Activity Lab). On until launch, because the
    /// owner tests TestFlight builds and can't run debug builds from Xcode.
    public var developerToolsEnabled: Bool
    /// RevenueCat's public API key for this app (`appl_…`, M7). Nil: Lockin Plus is sold through
    /// StoreKit 2 directly, without RevenueCat.
    public var revenueCatAPIKey: String?

    public init(
        appGroupIdentifier: String? = nil,
        apiHost: String? = nil,
        webHost: String? = nil,
        apnsEnvironment: APNsEnvironment? = nil,
        developerToolsEnabled: Bool = false,
        revenueCatAPIKey: String? = nil
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.apiHost = apiHost
        self.webHost = webHost
        self.apnsEnvironment = apnsEnvironment
        self.developerToolsEnabled = developerToolsEnabled
        self.revenueCatAPIKey = revenueCatAPIKey
    }

    /// `https://<apiHost>`, or nil without a host.
    ///
    /// A full URL is accepted too (the `https:/$()/host` xcconfig trick, or a value typed straight
    /// into Info.plist), and trailing slashes are dropped so paths can be appended cleanly.
    public var apiBaseURL: URL? {
        Self.baseURL(host: apiHost)
    }

    /// `https://<webHost>`, or `apiBaseURL` when there's no web host: the API Worker serves the
    /// pages too. Nil without either, and then the app shows no links to them.
    public var webBaseURL: URL? {
        Self.baseURL(host: webHost) ?? apiBaseURL
    }

    /// A page of the website (`<webBaseURL>/privacy` and so on), or nil without a host. App Review
    /// wants the privacy policy and terms linked from the paywall (Guideline 3.1.2), so a build for
    /// review needs `LK_WEB_HOST` or `LK_API_HOST`.
    public func webURL(_ page: WebPage) -> URL? {
        webBaseURL?.appending(component: page.path, directoryHint: .notDirectory)
    }

    /// The pages the app links to, as the Worker serves them (server/src/pages.ts).
    public enum WebPage: String, CaseIterable, Sendable {
        case privacy
        case terms
        case support

        /// The path under the site, without a leading slash.
        public var path: String { rawValue }
    }

    /// `https://<host>` from an xcconfig value: a host, or a full URL; trailing slashes dropped.
    private static func baseURL(host value: String?) -> URL? {
        guard var host = value else { return nil }
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
            webHost: value(InfoKey.webHost),
            apnsEnvironment: value(InfoKey.apnsEnvironment).flatMap { APNsEnvironment(parsing: $0) },
            developerToolsEnabled: flag(InfoKey.developerTools),
            revenueCatAPIKey: value(InfoKey.revenueCatKey)
        )
    }

    /// The configuration of the running app or extension.
    public static let main = AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])

    /// The Info.plist keys, as written by `project.yml`. The widget extension only has the App
    /// Group.
    public enum InfoKey {
        public static let appGroup = "LKAppGroupIdentifier"
        public static let apiHost = "LKAPIHost"
        public static let webHost = "LKWebHost"
        public static let apnsEnvironment = "LKAPNsEnvironment"
        public static let developerTools = "LKDeveloperTools"
        public static let revenueCatKey = "LKRevenueCatKey"
    }
}
