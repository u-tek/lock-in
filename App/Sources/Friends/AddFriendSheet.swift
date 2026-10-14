import API
import Creature
import DesignSystem
import Model
import Paywall
import Social
import SwiftUI

/// Add a friend or join a squad by code: type it or paste it (a link works too), then their
/// Locklings bounce in. An invite link's code goes through here too, as whichever it turns out
/// to be.
struct AddFriendSheet: View {
    enum Purpose: Equatable {
        /// "Add a friend".
        case friend
        /// "Join a squad". A friend's code works here as well: it adds the friend.
        case squad
        /// An invite link: a squad's code or a friend's, whichever it is.
        case link

        var title: LocalizedStringKey {
            switch self {
            case .friend: "Add a friend"
            case .squad: "Join a squad"
            case .link: "Invite"
            }
        }

        var placeholder: LocalizedStringKey {
            switch self {
            case .friend: "Friend code"
            case .squad: "Squad code"
            case .link: "Code"
            }
        }

        var action: LocalizedStringKey {
            switch self {
            case .friend, .link: "Add"
            case .squad: "Join"
            }
        }
    }

    /// What the code turned out to be.
    enum Added: Equatable {
        case friend(Friend)
        case squad(Squad)
    }

    enum Phase: Equatable {
        case entering
        case adding
        case added(Added)
    }

    @ObservedObject var friends: FriendsStore
    let squads: SquadsStore
    let plus: PlusStore
    /// Yours, for the paywall's header.
    let avatar: AvatarCode
    let purpose: Purpose
    let submitsAtOnce: Bool
    let focusesField: Bool

    @State private var code: String
    @State private var phase: Phase
    @State private var problem: String? = nil
    @State private var cheers = 0
    @State private var showsPaywall = false
    @FocusState private var fieldFocused: Bool
    @StateObject private var pasteboard = PasteRelay()
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - code: what's in the field to start with.
    ///   - submitsAtOnce: add straight away (an invite link's code).
    ///   - added: show the friend or squad as just added (snapshots).
    init(
        friends: FriendsStore,
        squads: SquadsStore,
        plus: PlusStore,
        avatar: AvatarCode,
        purpose: Purpose = .friend,
        code: String = "",
        submitsAtOnce: Bool = false,
        added: Added? = nil,
        focusesField: Bool = true
    ) {
        self.friends = friends
        self.squads = squads
        self.plus = plus
        self.avatar = avatar
        self.purpose = purpose
        self.submitsAtOnce = submitsAtOnce
        self.focusesField = focusesField
        _code = State(initialValue: Self.tidy(code))
        _phase = State(initialValue: added.map(Phase.added) ?? .entering)
    }

    private var isAdded: Bool {
        if case .added = phase { true } else { false }
    }

    private var isWellFormed: Bool {
        FriendCode.isWellFormed(code)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .added(.friend(let friend)):
                    added(friend)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .added(.squad(let squad)):
                    joined(squad)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .entering, .adding:
                    entry
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, LKSpacing.xl)
            .padding(.bottom, LKSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(isAdded ? Text(verbatim: "") : Text(purpose.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isAdded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.success, trigger: cheers)
        // A squad that's full, or one squad too many on the free plan (SPEC.md §2, moment 2).
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: avatar)
        .onChange(of: pasteboard.paste) { _, paste in
            if let paste {
                code = Self.tidy(paste.text)
            }
        }
        .task {
            if submitsAtOnce {
                add()
            } else if focusesField, !isAdded {
                try? await Task.sleep(for: .milliseconds(450))
                fieldFocused = true
            }
        }
    }

    // MARK: - Typing the code

    private var entry: some View {
        VStack(spacing: LKSpacing.l) {
            Spacer(minLength: LKSpacing.l)
            TextField(purpose.placeholder, text: $code)
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                .focused($fieldFocused)
                .onSubmit(add)
                .padding(.vertical, LKSpacing.l)
                .padding(.horizontal, LKSpacing.m)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .disabled(phase == .adding)
                .onChange(of: code) { _, typed in
                    let tidied = Self.tidy(typed)
                    if tidied != typed {
                        code = tidied
                    }
                    problem = nil
                }
            Text(message ?? " ")
                .font(LKFont.footnote)
                .foregroundStyle(LKColor.textSecondary)
                .multilineTextAlignment(.center)
            // The system's paste button: no "Allow Paste" prompt.
            PasteButton(payloadType: String.self) { @Sendable [pasteboard = self.pasteboard] strings in
                let text = strings.first ?? ""
                Task { @MainActor in
                    pasteboard.receive(text)
                }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            Spacer(minLength: LKSpacing.l)
            Button(action: add) {
                ZStack {
                    Text(purpose.action)
                        .opacity(phase == .adding ? 0 : 1)
                    if phase == .adding {
                        ProgressView()
                    }
                }
                .font(LKFont.headline)
                .frame(maxWidth: .infinity)
            }
            .lkProminentButton()
            .controlSize(.large)
            .disabled(!isWellFormed || phase == .adding)
        }
    }

    /// Why the code won't do, when there's a reason to say.
    private var message: String? {
        if let problem {
            return problem
        }
        if code.count == FriendCode.length, !isWellFormed {
            return "Codes don't use 0, O, 1 or I"
        }
        return nil
    }

    // MARK: - Added

    private func added(_ friend: Friend) -> some View {
        VStack(spacing: LKSpacing.l) {
            Spacer(minLength: 0)
            LocklingHero(avatar: friend.avatar, pose: .celebrating, size: 140, backdrop: .halo)
                .bump(on: cheers)
                .accessibilityHidden(true)
            VStack(spacing: LKSpacing.xs) {
                Text(friend.name)
                    .font(LKFont.largeTitle.weight(.bold))
                if let handle = friend.handle {
                    Text(verbatim: "@\(handle)")
                        .font(LKFont.body)
                        .foregroundStyle(LKColor.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Label {
                Text("You're friends")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(LKFont.subheadline.weight(.semibold))
            .foregroundStyle(LKColor.textSecondary)
            Spacer(minLength: 0)
            doneButton
        }
    }

    private func joined(_ squad: Squad) -> some View {
        VStack(spacing: LKSpacing.l) {
            Spacer(minLength: 0)
            SquadLocklings(
                members: squad.members,
                size: squad.members.count > 4 ? 56 : 72,
                limit: LiveActivityLimits.maxMembers,
                pose: .celebrating,
                ringColour: Color(uiColor: .systemBackground)
            )
            .bump(on: cheers)
            Text(squad.name)
                .font(LKFont.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Label {
                Text("You're in")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(LKFont.subheadline.weight(.semibold))
            .foregroundStyle(LKColor.textSecondary)
            Spacer(minLength: 0)
            doneButton
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(LKFont.headline)
                .frame(maxWidth: .infinity)
        }
        .lkProminentButton()
        .controlSize(.large)
    }

    // MARK: - Actions

    private func add() {
        guard isWellFormed, phase == .entering else { return }
        phase = .adding
        problem = nil
        Task {
            do {
                let added = try await redeem(code)
                fieldFocused = false
                withAnimation(.smooth) {
                    phase = .added(added)
                }
                // Once it's on screen, so the bounce shows.
                try? await Task.sleep(for: .milliseconds(150))
                cheers += 1
            } catch is CancellationError {
                phase = .entering
            } catch {
                phase = .entering
                if error.hitsFreeLimit {
                    showsPaywall = true
                } else if purpose == .friend {
                    problem = (error as? APIError)?.localizedDescription
                } else {
                    problem = error.squadMessage
                }
            }
        }
    }

    /// A friend's code adds the friend. A squad's code, or a link's, tries the squad first and
    /// falls back to a friend (`redeemInvite`), so whichever code it is just works.
    private func redeem(_ code: String) async throws -> Added {
        switch purpose {
        case .friend:
            let friend = try await friends.redeem(code: code)
            return .friend(friend)
        case .squad, .link:
            switch try await redeemInvite(code: code, squads: squads, friends: friends) {
            case .squad(let squad):
                return .squad(squad)
            case .friend(let friend):
                return .friend(friend)
            }
        }
    }

    /// The field's contents tidied as they're typed or pasted: a link gives up its code;
    /// otherwise uppercase letters and digits, at most eight.
    static func tidy(_ input: String) -> String {
        if input.count > FriendCode.length, let link = InviteLink(text: input) {
            return link.code
        }
        let kept = FriendCode.normalised(input).filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return String(kept.prefix(FriendCode.length))
    }
}

/// Carries what the paste button read to the main actor: the button may call back on any thread.
@MainActor
final class PasteRelay: ObservableObject {
    struct Paste: Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var paste: Paste? = nil

    func receive(_ text: String) {
        paste = Paste(text: text)
    }
}
