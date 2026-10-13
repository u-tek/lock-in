import Core
import DesignSystem
import SwiftUI

/// Tools for building and checking the app on a real phone: the owner tests TestFlight builds and
/// has no Xcode to read logs from, so what a build knows about itself is shown here. Reached from
/// Home while `LK_DEVELOPER_TOOLS` is YES (off for the App Store: M9).
struct DeveloperMenu: View {
    private let build = BuildInfo.current

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.apnsSpike) {
                    MenuRow(title: "APNs spike", detail: "Start a Live Activity and copy its push token", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink(value: AppRoute.liveActivityLab) {
                    MenuRow(title: "Live Activity Lab", detail: "Every presentation with made-up squads", systemImage: "rectangle.on.rectangle")
                }
                NavigationLink(value: AppRoute.designTokens) {
                    MenuRow(title: "Design tokens", detail: "Colours, type, spacing and components", systemImage: "paintpalette")
                }
            }
            .listRowBackground(LKColor.surface)

            Section {
                InfoRow(label: "Version", value: build.version)
                InfoRow(label: "Build", value: build.build)
                InfoRow(label: "APNs environment", value: build.apnsEnvironment)
                InfoRow(label: "API host", value: build.apiHost)
                InfoRow(label: "App Group", value: build.appGroup)
            } header: {
                Text("This build")
            } footer: {
                Text("TestFlight builds use production APNs, builds run from Xcode use sandbox. With no API host the app runs without a backend, which the APNs spike doesn't need.")
            }
            .listRowBackground(LKColor.surface)
        }
        .scrollContentBackground(.hidden)
        .lkScreenBackground()
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the running build was configured with, as display strings.
struct BuildInfo: Equatable {
    var version: String
    var build: String
    var apnsEnvironment: String
    var apiHost: String
    var appGroup: String

    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let configuration = AppConfiguration.main
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            apnsEnvironment: describe(APNsEnvironment.currentResolution),
            apiHost: configuration.apiHost ?? "not set",
            appGroup: configuration.appGroupIdentifier ?? "not set"
        )
    }

    /// "production, from the provisioning profile".
    static func describe(_ resolution: APNsEnvironment.Resolution) -> String {
        let source: String
        switch resolution.source {
        case .provisioningProfile: source = "from the provisioning profile"
        case .configuration: source = "from LK_APNS_ENV"
        case .fallback: source = "by default"
        }
        return "\(resolution.environment.rawValue), \(source)"
    }
}

private struct MenuRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: LKSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LKColor.accentText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LKFont.headline)
                    .foregroundStyle(LKColor.textPrimary)
                Text(detail)
                    .font(LKFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
            }
        }
        .padding(.vertical, LKSpacing.xxs)
    }
}

/// A label and a value that can be selected and copied (a host name, say).
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LKSpacing.m) {
            Text(label)
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textSecondary)
            Spacer(minLength: LKSpacing.s)
            Text(value)
                .font(LKFont.subheadline.monospaced())
                .foregroundStyle(LKColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
