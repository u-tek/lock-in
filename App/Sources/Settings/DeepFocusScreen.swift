import DeepFocus
import DesignSystem
import FamilyControls
import Model
import Paywall
import SwiftUI
import UIKit

/// Settings › Deep Focus (M8, Plus): block the apps you choose while you're locked in. Like a page
/// of Settings: one switch, one row for the apps, and a line on what "Open anyway" does.
///
/// Until Apple approves Family Controls the build has no entitlement and the page says it's coming
/// (docs/milestones/M8.md). Without Plus it offers Plus (SPEC.md §2, paywall moment 3).
struct DeepFocusScreen: View {
    @ObservedObject private var models: DeepFocusModels
    @ObservedObject private var authorization: DeepFocusAuthorization
    @ObservedObject private var plus: PlusStore
    private let avatar: AvatarCode

    @State private var showsPaywall = false
    @State private var showsPicker = false
    /// What the picker shows: loaded when it opens, saved when it hands back a change.
    @State private var picked = FamilyActivitySelection()
    /// What's saved, as last loaded or saved here, so loading isn't taken for a change.
    @State private var saved: FamilyActivitySelection? = nil
    @State private var isAsking = false
    @State private var problem: String? = nil
    @Environment(\.openURL) private var openURL

    /// The real thing: the app's Deep Focus models, which the session's coordinator also drives.
    init(plus: PlusStore, avatar: AvatarCode) {
        // Outside snapshot mode the app's services always exist; the preview keeps a stray
        // construction (snapshot mode builds Settings' rows too) away from Screen Time.
        let models = AppServices.live?.deepFocus.models ?? DeepFocusModels.preview(status: .notEntitled)
        self.init(models: models, plus: plus, avatar: avatar)
    }

    /// A fixed state, for snapshots: nothing touches Screen Time, the App Group or StoreKit.
    init(snapshot models: DeepFocusModels, isPlus: Bool, avatar: AvatarCode = .default) {
        self.init(models: models, plus: PlusStore.preview(isPlus: isPlus), avatar: avatar)
    }

    private init(models: DeepFocusModels, plus: PlusStore, avatar: AvatarCode) {
        _models = ObservedObject(wrappedValue: models)
        _authorization = ObservedObject(wrappedValue: models.authorization)
        _plus = ObservedObject(wrappedValue: plus)
        self.avatar = avatar
    }

    var body: some View {
        Form {
            if !plus.isPlus {
                offer
            } else {
                switch authorization.status {
                case .notEntitled:
                    comingSoon
                case .notDetermined:
                    askFirst
                case .denied:
                    denied
                case .approved:
                    settings
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Deep Focus")
        .navigationBarTitleDisplayMode(.inline)
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: avatar)
        .familyActivityPicker(isPresented: $showsPicker, selection: $picked)
        .onChange(of: picked) { _, selection in
            guard selection != saved else { return }
            saved = selection
            models.save(selection)
        }
        .errorAlert("Couldn't turn on Deep Focus", message: $problem)
    }

    // MARK: - Each state

    /// Not on Plus.
    private var offer: some View {
        Section {
            Text("Block distracting apps while you're locked in.")
            Button {
                showsPaywall = true
            } label: {
                Label("Get Lockin Plus", systemImage: LockinSymbol.plus)
            }
        }
    }

    /// Apple hasn't approved Family Controls for Lockin yet.
    private var comingSoon: some View {
        Section {
            LabeledContent("Deep Focus", value: "Coming soon")
        } footer: {
            Text("Waiting on Apple to approve app blocking for Lockin.")
        }
    }

    private var askFirst: some View {
        Section {
            Button("Turn on Deep Focus", action: ask)
                .disabled(isAsking)
        } footer: {
            Text("Screen Time asks first. Lockin never sees which apps you choose.")
        }
    }

    private var denied: some View {
        Section {
            LabeledContent("Screen Time", value: "Off")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } footer: {
            Text("Allow Lockin in Settings › Screen Time.")
        }
    }

    private var settings: some View {
        Section {
            Toggle("Block apps during sessions", isOn: $models.isOn)
            Button {
                let current = models.selection.load()
                saved = current
                picked = current
                showsPicker = true
            } label: {
                LabeledContent {
                    Text(models.summary.text)
                } label: {
                    Text("Choose apps")
                        .foregroundStyle(LKColor.textPrimary)
                }
            }
        } footer: {
            Text("Open anyway lets you in for 5 minutes. Your squad sees it.")
        }
    }

    // MARK: - Asking

    /// Screen Time's own prompt (Face ID or the passcode). Approved, the switch turns on: that's
    /// what the button said it would do.
    private func ask() {
        isAsking = true
        Task {
            defer { isAsking = false }
            do {
                try await authorization.request()
                if authorization.status == .approved {
                    models.isOn = true
                }
            } catch let failure as DeepFocusAuthorization.Failure {
                problem = failure.errorDescription
            } catch {
                problem = DeepFocusAuthorization.Failure.failed.errorDescription
            }
        }
    }
}
