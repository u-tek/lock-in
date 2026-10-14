import API
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

enum ProfileField: Hashable {
    case handle
    case name
}

/// The username and name rows, for the handle picker and Settings › Profile.
///
/// The username is checked as it's typed: this phone's verdict at once (`Moderation`, the same
/// rules as the server), then the server's after a pause in typing.
struct ProfileFields: View {
    @ObservedObject var account: AccountStore
    @Binding var handle: String
    @Binding var name: String
    @Binding var status: HandleStatus
    var focus: FocusState<ProfileField?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        Section {
            HStack(spacing: LKSpacing.xxs) {
                Text(verbatim: "@")
                    .foregroundStyle(LKColor.textSecondary)
                TextField("username", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                    .submitLabel(.next)
                    .focused(focus, equals: .handle)
                    .onSubmit {
                        focus.wrappedValue = .name
                    }
                HandleStatusIcon(status: status)
            }
            .font(LKFont.body.weight(.medium))
            .onChange(of: handle) { _, typed in
                let cleaned = Moderation.cleanHandleInput(typed)
                if cleaned != typed {
                    handle = cleaned
                }
            }
            .task(id: handle) {
                await check(handle)
            }
        } footer: {
            Text(handleMessage ?? " ")
        }

        Section {
            TextField("Name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused(focus, equals: .name)
                .onSubmit(onSubmit)
        } footer: {
            Text(nameMessage ?? " ")
        }
    }

    private func check(_ typed: String) async {
        let local = account.localHandleStatus(typed)
        status = local
        guard local == .checking else { return }
        // A pause in typing before the server is asked.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let checked = await account.checkHandle(typed)
        guard !Task.isCancelled else { return }
        status = checked
    }

    private var handleMessage: String? {
        switch status {
        case .invalid: "3–20 letters, numbers, _ or ., starting with a letter"
        case .notAllowed: "That one's not allowed. Try another."
        case .taken: "Already taken"
        case .unverified: "Couldn't check it just now"
        case .empty, .checking, .available, .yours: nil
        }
    }

    private var nameMessage: String? {
        let trimmed = Moderation.trimmed(name)
        guard !trimmed.isEmpty else { return nil }
        switch Moderation.checkName(trimmed) {
        case .ok: return nil
        case .notAllowed: return "That one's not allowed. Try another."
        case .invalid:
            return trimmed.unicodeScalars.count > Moderation.nameLength.upperBound ? "Up to 12 characters" : "That name won't work"
        }
    }
}

/// The username's verdict at the end of its field: a green tick, a red cross, or a spinner.
struct HandleStatusIcon: View {
    let status: HandleStatus

    var body: some View {
        Group {
            switch status {
            case .checking:
                ProgressView()
                    .controlSize(.small)
            case .available:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Available")
            case .taken, .notAllowed, .invalid:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Not available")
            case .empty, .yours, .unverified:
                EmptyView()
            }
        }
        .imageScale(.large)
        .transition(.scale.combined(with: .opacity))
        .animation(.snappy, value: status)
    }
}

/// After signing in for the first time: pick a username (and check the name Apple gave).
struct HandlePickerStep: View {
    @ObservedObject var account: AccountStore
    let avatar: AvatarCode
    let focusesField: Bool

    @State private var handle: String
    @State private var name: String
    @State private var status: HandleStatus = .empty
    @State private var isSaving = false
    @State private var failure: String? = nil
    @State private var cheers = 0
    @FocusState private var focus: ProfileField?

    init(account: AccountStore, user: User, avatar: AvatarCode, handle: String = "", focusesField: Bool = true) {
        self.account = account
        self.avatar = avatar
        self.focusesField = focusesField
        _handle = State(initialValue: handle)
        _name = State(initialValue: user.displayName ?? account.suggestedName ?? "")
    }

    private var canSave: Bool {
        status.canSave && Moderation.checkName(name) == .ok
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: LKSpacing.l) {
                    // Arms up when the name is free.
                    LocklingHero(avatar: avatar, pose: status == .available ? .celebrating : .idle, size: 104)
                        .bump(on: cheers)
                        .accessibilityHidden(true)
                    Text("Pick a username")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, LKSpacing.s)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            ProfileFields(account: account, handle: $handle, name: $name, status: $status, focus: $focus, onSubmit: save)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                ZStack {
                    Text("Continue")
                        .opacity(isSaving ? 0 : 1)
                    if isSaving {
                        ProgressView()
                    }
                }
                .font(LKFont.headline)
                .frame(maxWidth: .infinity)
            }
            .lkProminentButton()
            .controlSize(.large)
            .disabled(!canSave || isSaving)
            .padding(.horizontal, LKSpacing.xl)
            .padding(.bottom, LKSpacing.s)
        }
        .onChange(of: status) { _, status in
            if status == .available {
                cheers += 1
            }
        }
        .sensoryFeedback(.selection, trigger: cheers)
        .errorAlert("Couldn't save", message: $failure)
        .task {
            guard focusesField else { return }
            // After the sheet has settled, or the keyboard doesn't come up.
            try? await Task.sleep(for: .milliseconds(450))
            focus = .handle
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // The Lockling on this phone goes with it, so friends see the right one.
                try await account.setProfile(handle: handle, displayName: name, avatar: avatar)
            } catch let error as APIError {
                switch error.code {
                case .handleTaken: status = .taken
                case .handleInvalid: status = .invalid
                case .handleNotAllowed: status = .notAllowed
                default: failure = error.localizedDescription
                }
            } catch {
                // Cancelled: nothing to say.
            }
        }
    }
}

/// Settings › your account row: change your username or name.
struct ProfileEditSheet: View {
    @ObservedObject var account: AccountStore
    let user: User
    let avatar: AvatarCode

    @State private var handle: String
    @State private var name: String
    @State private var status: HandleStatus = .yours
    @State private var isSaving = false
    @State private var failure: String? = nil
    @FocusState private var focus: ProfileField?
    @Environment(\.dismiss) private var dismiss

    init(account: AccountStore, user: User, avatar: AvatarCode) {
        self.account = account
        self.user = user
        self.avatar = avatar
        _handle = State(initialValue: user.handle ?? "")
        _name = State(initialValue: user.displayName ?? "")
    }

    private var hasChanges: Bool {
        handle != (user.handle ?? "") || Moderation.trimmed(name) != (user.displayName ?? "")
    }

    private var canSave: Bool {
        hasChanges && status.canSave && Moderation.checkName(name) == .ok && !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FriendAvatar(avatar: avatar, size: 88)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                ProfileFields(account: account, handle: $handle, name: $name, status: $status, focus: $focus, onSubmit: save)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .errorAlert("Couldn't save", message: $failure)
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await account.setProfile(handle: handle, displayName: name)
                dismiss()
            } catch let error as APIError {
                switch error.code {
                case .handleTaken: status = .taken
                case .handleInvalid: status = .invalid
                case .handleNotAllowed: status = .notAllowed
                default: failure = error.localizedDescription
                }
            } catch {
                // Cancelled.
            }
        }
    }
}
