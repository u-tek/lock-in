import Foundation

/// The provisioning profile embedded in this app or extension, read for the two entitlements the
/// app needs to know at runtime: its App Groups and its APNs environment.
///
/// Only builds signed for development or ad hoc distribution carry one. TestFlight and App Store
/// builds don't, and neither does the simulator.
public struct ProvisioningProfile: Sendable, Equatable {
    public var applicationGroups: [String]
    /// The `aps-environment` entitlement: "development" or "production".
    public var apsEnvironment: String?

    public init(applicationGroups: [String] = [], apsEnvironment: String? = nil) {
        self.applicationGroups = applicationGroups
        self.apsEnvironment = apsEnvironment
    }

    /// Parses the contents of an `embedded.mobileprovision` file, or nil when there's no readable
    /// property list in it.
    ///
    /// The profile is a signed (CMS) envelope around an XML property list. Rather than unwrap the
    /// signature, the plist is found by its markers: the signature isn't ours to check, and the
    /// system has already verified it before the app could launch.
    public init?(data: Data) {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound],
                  format: nil
              ) as? [String: Any]
        else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        self.init(
            applicationGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            apsEnvironment: entitlements["aps-environment"] as? String
        )
    }

    /// The raw profile embedded in `bundle`, if there is one.
    public static func embeddedData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The running app's or extension's profile. Read once: it can't change while the process runs.
    public static let embedded: ProvisioningProfile? = embeddedData().flatMap { ProvisioningProfile(data: $0) }
}
