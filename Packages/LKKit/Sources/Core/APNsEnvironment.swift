import Foundation

/// Which APNs host this build's push tokens belong to.
///
/// A token only works against the host it was issued for, so the app reports the environment with
/// every token it uploads and the server stores it per token (SPEC.md §4.2). Builds signed by
/// Xcode get sandbox tokens; TestFlight and App Store builds get production tokens.
public enum APNsEnvironment: String, Codable, CaseIterable, Sendable {
    case sandbox
    case production

    /// Reads both spellings: the entitlement's ("development", "production") and ours ("sandbox",
    /// "production"), in any case. Anything else is nil.
    public init?(parsing value: String) {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "development", "sandbox": self = .sandbox
        case "production": self = .production
        default: return nil
        }
    }

    /// Where a resolved environment came from, so the Developer menu can say why.
    public enum Source: String, Sendable {
        /// The `aps-environment` entitlement of the embedded provisioning profile.
        case provisioningProfile
        /// `LKAPNsEnvironment` in Info.plist (`LK_APNS_ENV`).
        case configuration
        /// Neither was available.
        case fallback
    }

    public struct Resolution: Sendable, Equatable {
        public var environment: APNsEnvironment
        public var source: Source

        public init(environment: APNsEnvironment, source: Source) {
            self.environment = environment
            self.source = source
        }
    }

    /// Decides the environment from the embedded provisioning profile (its raw contents, nil when
    /// the bundle has none) and the configured value.
    ///
    /// The profile wins because it is what the token was actually issued under: a Release build
    /// signed for development still gets sandbox tokens. TestFlight and App Store builds carry no
    /// embedded profile, so without one the configured value is used, and without that,
    /// production, which is where every build Apple distributes ends up.
    public static func resolution(profileData: Data?, configured: APNsEnvironment?) -> Resolution {
        if let profileData,
           let entitlement = ProvisioningProfile(data: profileData)?.apsEnvironment,
           let environment = APNsEnvironment(parsing: entitlement) {
            return Resolution(environment: environment, source: .provisioningProfile)
        }
        if let configured {
            return Resolution(environment: configured, source: .configuration)
        }
        return Resolution(environment: .production, source: .fallback)
    }

    public static func resolve(profileData: Data?, configured: APNsEnvironment?) -> APNsEnvironment {
        resolution(profileData: profileData, configured: configured).environment
    }

    /// The running build's resolution. Read once: neither input changes while the app runs.
    public static let currentResolution = resolution(
        profileData: ProvisioningProfile.embeddedData(),
        configured: AppConfiguration.main.apnsEnvironment
    )

    /// The environment to report alongside this build's push tokens.
    public static var current: APNsEnvironment {
        currentResolution.environment
    }
}
