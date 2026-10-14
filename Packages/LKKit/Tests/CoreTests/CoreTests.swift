import Foundation
import Testing
@testable import Core

@Suite struct AppConfigurationTests {
    @Test func unsetBuildSettingsReadAsNil() {
        let configuration = AppConfiguration(infoDictionary: [
            "LKAppGroupIdentifier": "group.com.example.lockin",
            "LKAPIHost": "  ",
            "LKWebHost": "",
            "LKAPNsEnvironment": "",
            "LKDeveloperTools": "",
        ])
        #expect(configuration.appGroupIdentifier == "group.com.example.lockin")
        #expect(configuration.apiHost == nil)
        #expect(configuration.apiBaseURL == nil)
        #expect(configuration.webHost == nil)
        #expect(configuration.webBaseURL == nil)
        #expect(configuration.apnsEnvironment == nil)
        #expect(!configuration.developerToolsEnabled)
        #expect(AppConfiguration(infoDictionary: [:]) == AppConfiguration())
    }

    @Test func keysMatchProjectYML() {
        #expect(AppConfiguration.InfoKey.appGroup == "LKAppGroupIdentifier")
        #expect(AppConfiguration.InfoKey.apiHost == "LKAPIHost")
        #expect(AppConfiguration.InfoKey.webHost == "LKWebHost")
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

    /// M9: the privacy policy, terms and support page, which the paywall and Settings › About link
    /// to. On `LK_WEB_HOST` when it's set, else on the API host (the Worker serves both), else
    /// nowhere: the links hide rather than point at a placeholder.
    @Test func webPagesAreOnTheWebHostElseTheAPIHost() {
        let both = AppConfiguration(infoDictionary: ["LKAPIHost": "lockin-api.example.workers.dev", "LKWebHost": " lockin.app/ \n"])
        #expect(both.webHost == "lockin.app/")
        #expect(both.webBaseURL?.absoluteString == "https://lockin.app")
        #expect(both.webURL(.privacy)?.absoluteString == "https://lockin.app/privacy")
        #expect(both.webURL(.terms)?.absoluteString == "https://lockin.app/terms")
        #expect(both.webURL(.support)?.absoluteString == "https://lockin.app/support")
        // The API stays where it was.
        #expect(both.apiBaseURL?.absoluteString == "https://lockin-api.example.workers.dev")

        let apiOnly = AppConfiguration(infoDictionary: ["LKAPIHost": "lockin-api.example.workers.dev", "LKWebHost": ""])
        #expect(apiOnly.webHost == nil)
        #expect(apiOnly.webBaseURL?.absoluteString == "https://lockin-api.example.workers.dev")
        #expect(apiOnly.webURL(.terms)?.absoluteString == "https://lockin-api.example.workers.dev/terms")

        #expect(AppConfiguration(webHost: "https://example.com/site").webURL(.privacy)?.absoluteString == "https://example.com/site/privacy")
        #expect(AppConfiguration(webHost: "localhost:8787").webURL(.support)?.absoluteString == "https://localhost:8787/support")
    }

    /// No host at all (the simulator's default, and the snapshots'): no page has a URL, so nothing
    /// links to example.com or a half-made address.
    @Test func withoutAHostThereAreNoPages() {
        for configuration in [AppConfiguration(), AppConfiguration(infoDictionary: ["LKAPIHost": " ", "LKWebHost": "/"])] {
            #expect(configuration.webBaseURL == nil)
            for page in AppConfiguration.WebPage.allCases {
                #expect(configuration.webURL(page) == nil)
            }
        }
    }

    /// The paths the Worker serves the pages at (server/src/pages.ts, tested in
    /// server/test/pages.test.ts).
    @Test func pagePathsMatchTheWorker() {
        #expect(AppConfiguration.WebPage.allCases.map(\.path) == ["privacy", "terms", "support"])
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

    /// `fixtures/analytics/events.json` is the list the server's `POST /metrics` accepts
    /// (docs/decisions/0010-analytics-provider.md): exactly these names, in this order.
    @Test func theEventListMatchesTheSharedFixture() throws {
        let object = try #require(JSONSerialization.jsonObject(with: AnalyticsEventsFixture.data()) as? [String: Any])
        #expect(Set(object.keys) == ["events"])
        let names = try #require(object["events"] as? [String])
        #expect(names == AnalyticsEvent.allCases.map(\.rawValue))
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

/// `fixtures/analytics/events.json` at the repository root, found by walking up from this file as
/// the other shared fixtures are.
enum AnalyticsEventsFixture {
    struct NotFound: Error, CustomStringConvertible {
        let description: String
    }

    static func data() throws -> Data {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in url.pathComponents.indices {
            let candidate = url.appendingPathComponent("fixtures/analytics/events.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            url = url.deletingLastPathComponent()
        }
        throw NotFound(description: "No fixtures/analytics/events.json above \(#filePath)")
    }
}
