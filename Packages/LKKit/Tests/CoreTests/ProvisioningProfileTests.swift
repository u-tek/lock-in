import Foundation
import Testing
@testable import Core

/// A profile shaped like a real `embedded.mobileprovision`: an XML plist inside a signed envelope
/// of binary bytes.
func syntheticProfile(apsEnvironment: String?, groups: [String] = ["group.com.example.lockin"]) -> Data {
    let aps = apsEnvironment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
    let groupList = groups.map { "<string>\($0)</string>" }.joined()
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>AppIDName</key><string>Lockin</string>
    <key>Entitlements</key><dict>
    \(aps)
    <key>com.apple.security.application-groups</key><array>\(groupList)</array>
    <key>get-task-allow</key><true/>
    </dict>
    <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
    </dict></plist>
    """
    let header = Data([0x30, 0x82, 0x2C, 0x1F, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0])
    let signature = Data([0x00, 0xA0, 0x82, 0x0E, 0x3F, 0x30, 0x82, 0x04, 0x34, 0xFF])
    return header + Data(plist.utf8) + signature
}

@Suite struct ProvisioningProfileTests {
    @Test func readsAppGroupsAndTheAPNsEnvironment() throws {
        let data = syntheticProfile(apsEnvironment: "development", groups: ["group.com.example.lockin", "group.other"])
        let profile = try #require(ProvisioningProfile(data: data))
        #expect(profile.applicationGroups == ["group.com.example.lockin", "group.other"])
        #expect(profile.apsEnvironment == "development")
    }

    @Test func profileWithoutPushHasNoEnvironment() throws {
        let profile = try #require(ProvisioningProfile(data: syntheticProfile(apsEnvironment: nil)))
        #expect(profile.apsEnvironment == nil)
        #expect(profile.applicationGroups == ["group.com.example.lockin"])
    }

    @Test func rejectsDataWithoutAPlist() {
        #expect(ProvisioningProfile(data: Data()) == nil)
        #expect(ProvisioningProfile(data: Data([0x01, 0x02, 0x03])) == nil)
        // Cut off before the closing marker.
        let truncated = syntheticProfile(apsEnvironment: "production").prefix(200)
        #expect(ProvisioningProfile(data: Data(truncated)) == nil)
    }

    @Test func noProfileInTheTestBundle() {
        #expect(ProvisioningProfile.embeddedData(bundle: Bundle(for: BundleMarker.self)) == nil)
    }
}

@Suite struct APNsEnvironmentTests {
    @Test func theProfileWins() {
        let development = syntheticProfile(apsEnvironment: "development")
        let production = syntheticProfile(apsEnvironment: "production")

        #expect(APNsEnvironment.resolve(profileData: development, configured: .production) == .sandbox)
        #expect(APNsEnvironment.resolve(profileData: production, configured: .sandbox) == .production)
        #expect(
            APNsEnvironment.resolution(profileData: development, configured: nil)
                == APNsEnvironment.Resolution(environment: .sandbox, source: .provisioningProfile)
        )
    }

    @Test func withoutAProfileTheConfiguredValueIsUsed() {
        // TestFlight and App Store builds: no embedded profile.
        #expect(
            APNsEnvironment.resolution(profileData: nil, configured: .sandbox)
                == APNsEnvironment.Resolution(environment: .sandbox, source: .configuration)
        )
        #expect(APNsEnvironment.resolve(profileData: nil, configured: .production) == .production)
    }

    @Test func withNothingItIsProduction() {
        #expect(
            APNsEnvironment.resolution(profileData: nil, configured: nil)
                == APNsEnvironment.Resolution(environment: .production, source: .fallback)
        )
    }

    @Test func anUnreadableProfileFallsThrough() {
        let withoutPush = syntheticProfile(apsEnvironment: nil)
        let unknown = syntheticProfile(apsEnvironment: "staging")
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])

        #expect(APNsEnvironment.resolve(profileData: withoutPush, configured: .sandbox) == .sandbox)
        #expect(APNsEnvironment.resolve(profileData: unknown, configured: .sandbox) == .sandbox)
        #expect(APNsEnvironment.resolve(profileData: garbage, configured: nil) == .production)
    }

    @Test(arguments: [
        ("development", APNsEnvironment.sandbox),
        ("sandbox", APNsEnvironment.sandbox),
        ("Development", APNsEnvironment.sandbox),
        ("production", APNsEnvironment.production),
        (" PRODUCTION\n", APNsEnvironment.production),
    ])
    func parsesBothSpellings(value: String, expected: APNsEnvironment) {
        #expect(APNsEnvironment(parsing: value) == expected)
    }

    @Test func rejectsOtherValues() {
        for value in ["", "staging", "prod", "dev"] {
            #expect(APNsEnvironment(parsing: value) == nil)
        }
    }

    @Test func encodesAsTheNameTheServerExpects() throws {
        let data = try JSONEncoder().encode([APNsEnvironment.sandbox, .production])
        #expect(String(decoding: data, as: UTF8.self) == #"["sandbox","production"]"#)
    }
}

private final class BundleMarker {}
