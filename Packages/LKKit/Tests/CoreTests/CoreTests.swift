import Foundation
import Testing
@testable import Core

@Suite struct AppConfigurationTests {
    @Test func unsetBuildSettingsReadAsNil() {
        let configuration = AppConfiguration(infoDictionary: [
            "LKAppGroupIdentifier": "group.com.example.lockin",
            "LKAPIHost": "  ",
            "LKAPNsEnvironment": "",
            "LKDeveloperTools": "",
        ])
        #expect(configuration.appGroupIdentifier == "group.com.example.lockin")
        #expect(configuration.apiHost == nil)
        #expect(configuration.apiBaseURL == nil)
        #expect(configuration.apnsEnvironment == nil)
        #expect(!configuration.developerToolsEnabled)
        #expect(AppConfiguration(infoDictionary: [:]) == AppConfiguration())
    }

    @Test func keysMatchProjectYML() {
        #expect(AppConfiguration.InfoKey.appGroup == "LKAppGroupIdentifier")
        #expect(AppConfiguration.InfoKey.apiHost == "LKAPIHost")
        #expect(AppConfiguration.InfoKey.apnsEnvironment == "LKAPNsEnvironment")
        #expect(AppConfiguration.InfoKey.developerTools == "LKDeveloperTools")
        #expect(AppConfiguration.InfoKey.revenueCatKey == "LKRevenueCatKey")
    }

    /// M7: RevenueCat's public key, from `LK_REVENUECAT_KEY`. Empty (the default) sells Plus
    /// through StoreKit 2.
    @Test func theRevenueCatKeyIsReadWhenSet() {
        #expect(AppConfiguration(infoDictionary: ["LKRevenueCatKey": " appl_TestKey123 \n"]).revenueCatAPIKey == "appl_TestKey123")
        #expect(AppConfiguration(infoDictionary: ["LKRevenueCatKey": ""]).revenueCatAPIKey == nil)
        #expect(AppConfiguration(infoDictionary: [:]).revenueCatAPIKey == nil)
    }

    @Test func apiBaseURLIsHTTPSOnTheHost() {
        let configuration = AppConfiguration(infoDictionary: ["LKAPIHost": " lockin-api.example.workers.dev "])
        #expect(configuration.apiHost == "lockin-api.example.workers.dev")
        #expect(configuration.apiBaseURL?.absoluteString == "https://lockin-api.example.workers.dev")
        #expect(AppConfiguration(apiHost: "lockin-api.example.workers.dev/").apiBaseURL?.absoluteString == "https://lockin-api.example.workers.dev")
        #expect(AppConfiguration(apiHost: "localhost:8787").apiBaseURL?.absoluteString == "https://localhost:8787")
        #expect(AppConfiguration(apiHost: "https://api.example.com").apiBaseURL?.absoluteString == "https://api.example.com")
        #expect(AppConfiguration(apiHost: "/").apiBaseURL == nil)
    }

    @Test(arguments: [
        ("YES", true),
        ("yes", true),
        ("true", true),
        ("1", true),
        (" YES ", true),
        ("NO", false),
        ("0", false),
        ("false", false),
        ("", false),
        ("$(LK_DEVELOPER_TOOLS)", false),
    ])
    func developerToolsFlag(value: String, expected: Bool) {
        let configuration = AppConfiguration(infoDictionary: ["LKDeveloperTools": value])
        #expect(configuration.developerToolsEnabled == expected)
    }

    @Test func developerToolsFlagAcceptsAPlistBoolean() {
        #expect(AppConfiguration(infoDictionary: ["LKDeveloperTools": true]).developerToolsEnabled)
        #expect(!AppConfiguration(infoDictionary: ["LKDeveloperTools": false]).developerToolsEnabled)
    }

    @Test func readsTheConfiguredAPNsEnvironment() {
        #expect(AppConfiguration(infoDictionary: ["LKAPNsEnvironment": "sandbox"]).apnsEnvironment == .sandbox)
        #expect(AppConfiguration(infoDictionary: ["LKAPNsEnvironment": "production"]).apnsEnvironment == .production)
        #expect(AppConfiguration(infoDictionary: ["LKAPNsEnvironment": "staging"]).apnsEnvironment == nil)
    }
}

@Suite struct AnalyticsTests {
    @Test func sendsTheEventNameAndIntegerCountsOnly() {
        let recorder = Recorder()
        let analytics = Analytics { name, parameters in recorder.record(name, parameters) }

        analytics.track(.sessionCompleted, counts: ["minutes": 25, "members": 3])
        analytics.track(.appOpened)

        #expect(recorder.events == [
            Recorder.Event(name: "session.completed", parameters: ["minutes": "25", "members": "3"]),
            Recorder.Event(name: "app.opened", parameters: [:]),
        ])
        // Every value that reaches a sink reads back as an integer.
        for event in recorder.events {
            let allIntegers = event.parameters.values.allSatisfy { Int($0) != nil }
            #expect(allIntegers)
        }
    }

    @Test func eventNamesAreUniqueAndScoped() {
        let names = AnalyticsEvent.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        for name in names {
            let parts = name.split(separator: ".")
            #expect(parts.count == 2, "\(name) should read area.action")
        }
    }

    @Test func deepFocusSlipsAreCounted() {
        #expect(AnalyticsEvent.deepFocusSlip.rawValue == "deepFocus.slip")
    }

    @Test func disabledAndDebugSinksAcceptEveryEvent() {
        for event in AnalyticsEvent.allCases {
            Analytics.disabled.track(event, counts: ["n": 1])
            Analytics.debugLog.track(event, counts: ["n": 1])
        }
    }
}

@Suite struct ShortIDTests {
    @Test func madeIdsAreTenBase62Characters() {
        var generator = SplitMix64(seed: 42)
        let alphabet = Set(ShortID.alphabet)
        for _ in 0..<1_000 {
            let id = ShortID.make(using: &generator)
            #expect(id.count == 10)
            let inAlphabet = id.allSatisfy { alphabet.contains($0) }
            #expect(inAlphabet)
            #expect(ShortID.isValid(id))
        }
        #expect(ShortID.isValid(ShortID.make()))
    }

    @Test func alphabetIsBase62() {
        #expect(ShortID.alphabet.count == 62)
        #expect(Set(ShortID.alphabet).count == 62)
    }

    @Test func seededGeneratorsRepeatAndIdsDontCollide() {
        var first = SplitMix64(seed: 7)
        var second = SplitMix64(seed: 7)
        let ids = (0..<10_000).map { _ in ShortID.make(using: &first) }
        let again = (0..<10_000).map { _ in ShortID.make(using: &second) }
        #expect(ids == again)
        #expect(Set(ids).count == ids.count)
    }

    @Test func usesTheWholeAlphabet() {
        var generator = SplitMix64(seed: 2026)
        let seen = Set((0..<1_000).flatMap { _ in ShortID.make(using: &generator) })
        #expect(seen == Set(ShortID.alphabet))
    }

    @Test(arguments: [
        "",
        "abc",
        "r7Kq2xP9a",
        "r7Kq2xP9aLx",
        "r7Kq2xP9a-",
        "r7Kq2xP9a_",
        "r7Kq2xP9a ",
        "r7Kq2xP9aÄ",
        "r7Kq2xP9🦊",
        "０１２３４５６７８９",
    ])
    func rejectsAnythingElse(id: String) {
        #expect(!ShortID.isValid(id))
    }

    @Test func acceptsFixtureIds() {
        for id in ["r7Kq2xP9aL", "Av4Nq8sT2b", "s0LoRun123", "zZ9yY8xX70", "0000000000", "zzzzzzzzzz"] {
            #expect(ShortID.isValid(id))
        }
    }
}

@Suite struct AppGroupTests {
    @Test func fallsBackToTheConfiguredIdentifier() {
        // No provisioning profile in tests, so the configured group is the only candidate.
        let configuration = AppConfiguration(appGroupIdentifier: "group.com.example.lockin.tests")
        #expect(AppGroup.identifier(configuration: configuration) == "group.com.example.lockin.tests")
    }

    @Test func createsDirectoriesWithTheirBackupSetting() throws {
        for directory in AppGroup.Directory.allCases {
            let url = try AppGroup.directory(directory, configuration: AppConfiguration())
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            #expect(exists)
            #expect(isDirectory.boolValue)
            #expect(url.lastPathComponent == directory.rawValue)
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == directory.isExcludedFromBackup)
        }
        #expect(AppGroup.Directory.database.isExcludedFromBackup == false)
        #expect(AppGroup.Directory.widget.isExcludedFromBackup)
    }

    @Test func defaultsAreAlwaysAvailable() {
        #expect(AppGroup.defaults(configuration: AppConfiguration()) != nil)
    }
}

/// SplitMix64: a tiny seeded generator, so id tests are repeatable.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class Recorder: @unchecked Sendable {
    struct Event: Equatable {
        var name: String
        var parameters: [String: String]
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ name: String, _ parameters: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(Event(name: name, parameters: parameters))
    }
}
