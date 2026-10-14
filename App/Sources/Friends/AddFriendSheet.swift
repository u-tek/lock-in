import API
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

/// Add a friend by their code: type it or paste it (a link works too), then their Lockling
/// bounces in.
struct AddFriendSheet: View {
    enum Phase: Equatable {
        case entering
        case adding
        case added(Friend)
    }

    @ObservedObject var friends: FriendsStore
    let submitsAtOnce: Bool
    let focusesField: Bool

    @State private var code: String
    @State private var phase: Phase
    @State private var problem: String? = nil
    @State private var cheers = 0
    @FocusState private var fieldFocused: Bool
    @StateObject private var pasteboard = PasteRelay()
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - code: what's in the field to start with.
    ///   - submitsAtOnce: add straight away (an invite link's code).
    ///   - added: show the friend as just added (snapshots).
    init(friends: FriendsStore, code: String = "", submitsAtOnce: Bool = false, added: Friend? = nil, focusesField: Bool = true) {
        self.friends = friends
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
                case .added(let friend):
                    added(friend)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .entering, .adding:
                    entry
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, LKSpacing.xl)
            .padding(.bottom, LKSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(isAdded ? Text(verbatim: "") : Text("Add a friend"))
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
            TextField("Friend code", text: $code)
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
                    Text("Add")
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
    }

    // MARK: - Actions

    private func add() {
        guard isWellFormed, phase == .entering else { return }
        phase = .adding
        problem = nil
        Task {
            do {
                let friend = try await friends.redeem(code: code)
                fieldFocused = false
                withAnimation(.smooth) {
                    phase = .added(friend)
                }
                // Once it's on screen, so the bounce shows.
                try? await Task.sleep(for: .milliseconds(150))
                cheers += 1
            } catch let error as APIError {
                phase = .entering
                problem = error.localizedDescription
            } catch {
                phase = .entering
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
