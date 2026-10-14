import Core
import DesignSystem
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
