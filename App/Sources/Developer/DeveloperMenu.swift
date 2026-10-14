import Core
import DesignSystem
import Notifications
import SwiftUI

/// Tools for building and checking the app on a real phone: the owner tests TestFlight builds and
/// has no Xcode to read logs from, so what a build knows about itself is shown here. Reached from
/// Settings by tapping the version five times, while `LK_DEVELOPER_TOOLS` is YES (off for the App
/// Store: M9).
///
/// Laid out like a page of Settings: rows with coloured icon tiles that push the tools, then the
/// build's facts as label and value.
struct DeveloperMenu: View {
    private let build = BuildInfo.current
    /// The push-to-start spike's switch (docs/spikes/push-to-start.md). Snapshots never read the
    /// App Group, so it shows off there.
    @State private var joinsWithoutOpening = SnapshotMode.current == nil && JoinWithoutOpening.isEnabled()
    @State private var lastAttempt: JoinWithoutOpening.Attempt? = nil

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.apnsSpike) {
                    MenuRow(title: "APNs spike", systemImage: "antenna.radiowaves.left.and.right", color: .green)
                }
                NavigationLink(value: AppRoute.liveActivityLab) {
                    MenuRow(title: "Live Activity Lab", systemImage: "testtube.2", color: .purple)
                }
                NavigationLink(value: AppRoute.designTokens) {
                    MenuRow(title: "Design tokens", systemImage: "paintpalette.fill", color: .pink)
                }
            }

            pushToStartSpike

            Section {
                LabeledContent("Version", value: build.version)
                LabeledContent("Build", value: build.build)
                LabeledContent {
                    Text(build.apnsEnvironment)
                } label: {
                    // A second Text in the label is the row's subtitle.
                    Text("APNs environment")
                    Text(build.apnsSource)
                }
                LabeledContent("API host", value: build.apiHost ?? BuildInfo.notSet)
                LabeledContent("App Group", value: build.appGroup ?? BuildInfo.notSet)
            } header: {
                Text("Build")
            } footer: {
                Text("TestFlight builds use production APNs, builds run from Xcode use sandbox. With no API host the app runs without a backend, which the APNs spike doesn't need.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if SnapshotMode.current == nil {
                lastAttempt = JoinWithoutOpening.lastAttempt()
            }
        }
    }

    /// "Join without opening": Join 25 and Join 50 run in the background and the server starts
    /// the Live Activity by push. Off by default until the spike says it's reliable.
    private var pushToStartSpike: some View {
        Section {
            Toggle(isOn: $joinsWithoutOpening) {
                MenuRow(title: "Join without opening", systemImage: "bolt.fill", color: .orange)
            }
            .onChange(of: joinsWithoutOpening) { _, isOn in
                guard SnapshotMode.current == nil else { return }
                JoinWithoutOpening.setEnabled(isOn)
                SquadAlerts.registerCategories(joinsInBackground: isOn)
            }
            if let lastAttempt {
                LabeledContent {
                    Text(Self.describe(lastAttempt))
                } label: {
                    Text("Last background join")
                    Text(Date(timeIntervalSince1970: lastAttempt.at).formatted(date: .abbreviated, time: .standard))
                }
            }
        } header: {
            Text("Push-to-start spike")
        } footer: {
            Text("Join 25 and Join 50 on a squad alert run without opening Lockin, and the server starts the Live Activity.")
        }
    }

    /// "Pushed to start, 1.8 s".
    private static func describe(_ attempt: JoinWithoutOpening.Attempt) -> String {
        let outcome = switch attempt.outcome {
        case .pushedToStart: "Pushed to start"
        case .notPushed: "Not pushed"
        case .failed: "Join failed"
        case .timedOut: "Timed out"
        }
        return "\(outcome), \(attempt.seconds.formatted(.number.precision(.fractionLength(1)))) s"
    }
}

/// What the running build was configured with, as display strings.
struct BuildInfo: Equatable {
    var version: String
    var build: String
    /// "production" or "sandbox".
    var apnsEnvironment: String
    /// Where the APNs environment came from: "From the provisioning profile".
    var apnsSource: String
    /// Nil when the build has none.
    var apiHost: String?
    var appGroup: String?

    /// What a row says for a setting the build doesn't have.
    static let notSet = "Not set"

    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let configuration = AppConfiguration.main
        let resolution = APNsEnvironment.currentResolution
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "Unknown",
            build: info["CFBundleVersion"] as? String ?? "Unknown",
            apnsEnvironment: resolution.environment.rawValue,
            apnsSource: source(of: resolution),
            apiHost: configuration.apiHost,
            appGroup: configuration.appGroupIdentifier
        )
    }

    /// "From the provisioning profile": why the build uses the environment it does.
    static func source(of resolution: APNsEnvironment.Resolution) -> String {
        switch resolution.source {
        case .provisioningProfile: "From the provisioning profile"
        case .configuration: "From LK_APNS_ENV"
        case .fallback: "By default"
        }
    }
}

/// A Settings row: an icon tile and a title. The NavigationLink around it adds the chevron.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            LKIconTile(systemName: systemImage, color: color)
        }
    }
}
