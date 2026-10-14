import Core
import Creature
import DesignSystem
import Model
import Paywall
import SessionEngine
import SwiftUI
import UIKit

/// Settings, as a sheet from Home: Plus, notifications, your Lockling, and the version. Tapping
/// the version five times shows the developer tools, in builds that have them
/// (`LK_DEVELOPER_TOOLS`); nothing else leads to them.
struct SettingsScreen: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore
    let onClose: () -> Void

    @State private var path: [AppRoute] = []
    @State private var showsPaywall = false
    @State private var editsLockling = false
    @State private var versionTaps = 0
    @Environment(\.openURL) private var openURL

    private static let tapsToReveal = 5

    private var showsDeveloper: Bool {
        AppConfiguration.main.developerToolsEnabled && versionTaps >= Self.tapsToReveal
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        showsPaywall = true
                    } label: {
                        LabeledContent {
                            Text(plus.isPlus ? "Active" : "Try free")
                        } label: {
                            Label {
                                Text("Lockin Plus")
                                    .foregroundStyle(LKColor.textPrimary)
                            } icon: {
                                LKIconTile(systemName: LockinSymbol.plus, color: LockinColour.plus)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label {
                            Text("Notifications")
                                .foregroundStyle(LKColor.textPrimary)
                        } icon: {
                            LKIconTile(systemName: "bell.badge.fill", color: .red)
                        }
                    }
                    Button {
                        editsLockling = true
                    } label: {
                        Label {
                            Text("Edit Lockling")
                                .foregroundStyle(LKColor.textPrimary)
                        } icon: {
                            LocklingTile(avatar: engine.avatar)
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                versionTaps += 1
                            }
                        }
                } header: {
                    Text("About")
                } footer: {
                    Text("Made for focusing together.")
                }

                if showsDeveloper {
                    developerSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                route.destination
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: engine.avatar)
        .sheet(isPresented: $editsLockling) {
            EditLocklingSheet(engine: engine, plus: plus)
        }
    }

    private var developerSection: some View {
        Section {
            NavigationLink(value: AppRoute.apnsSpike) {
                ToolRow(title: "APNs spike", systemImage: "antenna.radiowaves.left.and.right", color: .green)
            }
            NavigationLink(value: AppRoute.liveActivityLab) {
                ToolRow(title: "Live Activity Lab", systemImage: "testtube.2", color: .purple)
            }
            NavigationLink(value: AppRoute.designTokens) {
                ToolRow(title: "Design tokens", systemImage: "paintpalette.fill", color: .pink)
            }
            NavigationLink(value: AppRoute.developer) {
                ToolRow(title: "Build", systemImage: "hammer.fill", color: .gray)
            }
        } header: {
            Text("Developer")
        }
    }

    /// "0.1.0 (12)": the version and the build.
    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// A Settings row: an icon tile and a title.
private struct ToolRow: View {
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

/// Your Lockling as a row icon, on a tile of its own colour.
private struct LocklingTile: View {
    let avatar: AvatarCode
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = LKIconTile.defaultSize

    var body: some View {
        CreatureView(avatar: avatar, pose: .idle, size: side * 0.78)
            .frame(width: side, height: side)
            .background(
                CreatureCatalogue.colour(avatar.colour).opacity(0.2),
                in: RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Settings › Edit Lockling: the same maker as onboarding, saved only on Save.
struct EditLocklingSheet: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore

    @State private var draft: AvatarCode
    @State private var showsPaywall = false
    @Environment(\.dismiss) private var dismiss

    init(engine: SessionEngine, plus: PlusStore) {
        self.engine = engine
        self.plus = plus
        _draft = State(initialValue: engine.avatar)
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                LocklingEditor(avatar: $draft, isPlus: plus.isPlus, onLockedOption: { showsPaywall = true })
                Spacer(minLength: 0)
            }
            .navigationTitle("Your Lockling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        engine.avatar = draft
                        dismiss()
                    }
                    .disabled(draft == engine.avatar)
                }
            }
        }
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: draft)
    }
}
