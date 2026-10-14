import API
import Core
import Creature
import DesignSystem
import Model
import Paywall
import SessionEngine
import Social
import SwiftUI
import UIKit

/// Settings, as a sheet from Home: your account, Plus, notifications, your Lockling, and the
/// version. Tapping the version five times shows the developer tools, in builds that have them
/// (`LK_DEVELOPER_TOOLS`); nothing else leads to them.
struct SettingsScreen: View {
    enum AccountSheet: String, Identifiable {
        case signIn
        case profile

        var id: String { rawValue }
    }

    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore
    @ObservedObject var account: AccountStore
    let social: SocialModels
    let onClose: () -> Void

    @State private var path: [AppRoute] = []
    @State private var showsPaywall = false
    @State private var editsLockling = false
    @State private var accountSheet: AccountSheet? = nil
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var failure: String? = nil
    @State private var versionTaps = 0

    init(engine: SessionEngine, plus: PlusStore, social: SocialModels, onClose: @escaping () -> Void) {
        self.engine = engine
        self.plus = plus
        self.account = social.account
        self.social = social
        self.onClose = onClose
    }

    private static let tapsToReveal = 5

    private var showsDeveloper: Bool {
        AppConfiguration.main.developerToolsEnabled && versionTaps >= Self.tapsToReveal
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                accountSection

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
                    // Squad alerts and quiet hours (M4).
                    NavigationLink {
                        NotificationSettingsScreen()
                    } label: {
                        ToolRow(title: "Notifications", systemImage: "bell.badge.fill", color: .red)
                    }
                    // Blocking apps during sessions (M8, Plus).
                    NavigationLink {
                        DeepFocusScreen(plus: plus, avatar: engine.avatar)
                    } label: {
                        HStack {
                            ToolRow(title: "Deep Focus", systemImage: "lock.shield.fill", color: .indigo)
                            if !plus.isPlus {
                                Spacer()
                                PlusBadge()
                            }
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
        .sheet(item: $accountSheet) { sheet in
            switch sheet {
            case .signIn:
                FriendsFlow(social: social, plus: plus, avatar: engine.avatar, purpose: .signIn)
            case .profile:
                if let user = account.user {
                    ProfileEditSheet(account: account, user: user, avatar: engine.avatar)
                }
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: deleteAccount)
        } message: {
            Text("This deletes your friends and history from the Lockin server, and can't be undone. Your Lockling and sessions on this iPhone stay.")
        }
        .errorAlert("Couldn't delete your account", message: $failure)
    }

    // MARK: - Account

    /// Signed in: who you are, blocked people, signing out and deleting the account. Signed out:
    /// a way in. Nothing without a server (docs/milestones/M2.md).
    @ViewBuilder
    private var accountSection: some View {
        if account.isConfigured {
            switch account.state {
            case .signedOut:
                Section {
                    Button {
                        accountSheet = .signIn
                    } label: {
                        Label {
                            Text("Sign in")
                                .foregroundStyle(LKColor.textPrimary)
                        } icon: {
                            LKIconTile(systemName: "person.crop.circle.fill", color: LKColor.tint)
                        }
                    }
                }
            case .needsHandle:
                Section {
                    Button {
                        accountSheet = .signIn
                    } label: {
                        Label {
                            Text("Pick a username")
                                .foregroundStyle(LKColor.textPrimary)
                        } icon: {
                            LKIconTile(systemName: "at", color: LKColor.tint)
                        }
                    }
                }
            case .signedIn(let user):
                Section {
                    Button {
                        accountSheet = .profile
                    } label: {
                        ProfileRow(user: user, avatar: engine.avatar)
                    }
                    NavigationLink {
                        BlockedScreen(friends: social.friends)
                    } label: {
                        ToolRow(title: "Blocked people", systemImage: "hand.raised.fill", color: .gray)
                    }
                    Button("Sign out") {
                        account.signOut()
                    }
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        HStack {
                            Text("Delete account")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeleting)
                } header: {
                    Text("Account")
                }
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await account.deleteAccount()
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
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
            NavigationLink(value: AppRoute.petLab) {
                ToolRow(title: "Pet Lab", systemImage: "pawprint.fill", color: .orange)
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

/// You, at the top of Settings: your Lockling, name and @handle.
private struct ProfileRow: View {
    let user: User
    let avatar: AvatarCode

    var body: some View {
        HStack(spacing: LKSpacing.m) {
            FriendAvatar(avatar: avatar, size: 52)
            VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                Text(user.displayName ?? user.handle ?? "")
                    .font(LKFont.headline)
                    .foregroundStyle(LKColor.textPrimary)
                if let handle = user.handle {
                    Text(verbatim: "@\(handle)")
                        .font(LKFont.subheadline)
                        .foregroundStyle(LKColor.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, LKSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit your profile")
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
