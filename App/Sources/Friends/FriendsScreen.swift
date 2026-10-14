import API
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

/// Your code (big, as a QR code, and as a link to share), a way to add a friend by theirs, and
/// your friends. Squads arrive in M3.
struct FriendsScreen: View {
    enum Sheet: Identifiable {
        /// A code from an invite link is added straight away.
        case add(code: String?)
        case qr(FriendCode)
        case report(Friend)

        var id: String {
            switch self {
            case .add: "add"
            case .qr: "qr"
            case .report(let person): "report.\(person.id)"
            }
        }
    }

    @ObservedObject var account: AccountStore
    @ObservedObject var friends: FriendsStore
    let onDone: () -> Void

    @State private var sheet: Sheet? = nil
    @State private var removing: Friend? = nil
    @State private var blocking: Friend? = nil
    @State private var failure: String? = nil

    init(account: AccountStore, friends: FriendsStore, sheet: Sheet? = nil, onDone: @escaping () -> Void) {
        self.account = account
        self.friends = friends
        self.onDone = onDone
        _sheet = State(initialValue: sheet)
    }

    var body: some View {
        NavigationStack {
            List {
                codeSection
                friendsContent
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .refreshable {
                await friends.refresh()
            }
            .confirmationDialog(
                Text("Remove \(removing?.name ?? "")?"),
                isPresented: isPresent($removing),
                titleVisibility: .visible,
                presenting: removing
            ) { person in
                Button("Remove", role: .destructive) {
                    perform { try await friends.remove(person) }
                }
            } message: { _ in
                Text("You can add each other again with a code.")
            }
        }
        .confirmationDialog(
            Text("Block \(blocking?.name ?? "")?"),
            isPresented: isPresent($blocking),
            titleVisibility: .visible,
            presenting: blocking
        ) { person in
            Button("Block", role: .destructive) {
                perform { try await friends.block(person) }
            }
        } message: { _ in
            Text("They won't be able to add you, and you'll stop being friends.")
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add(let code):
                AddFriendSheet(friends: friends, code: code ?? "", submitsAtOnce: code != nil)
            case .qr(let code):
                QRCodeSheet(code: code)
            case .report(let person):
                ReportSheet(friends: friends, person: person)
            }
        }
        .errorAlert("Something went wrong", message: $failure)
        .task {
            await friends.refresh()
        }
        // An invite link opened while signed in (or just after signing in): add that friend.
        .onChange(of: friends.pendingInviteCode, initial: true) {
            if let code = friends.takePendingInvite() {
                sheet = .add(code: code)
            }
        }
    }

    // MARK: - Your code

    private var codeSection: some View {
        Section {
            HStack(spacing: LKSpacing.l) {
                Text(verbatim: FriendCode.spaced(friends.code?.code ?? "XXXXXXXX"))
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .speechSpellsOutCharacters()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                    .redacted(reason: friends.code == nil ? .placeholder : [])
                Spacer(minLength: 0)
                qrButton
            }
            .padding(.vertical, LKSpacing.xs)

            if !friends.friends.isEmpty {
                inviteLink { Label("Invite friends", systemImage: "square.and.arrow.up") }
            }
            Button {
                sheet = .add(code: nil)
            } label: {
                Label("Add a friend", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Your code")
        }
    }

    private var qrButton: some View {
        Button {
            if let code = friends.code {
                sheet = .qr(code)
            }
        } label: {
            Group {
                if let code = friends.code {
                    QRCodeImage(text: code.url.absoluteString)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                }
            }
            .frame(width: 52, height: 52)
            .padding(6)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(friends.code == nil)
        .accessibilityLabel("Show QR code")
    }

    /// The share sheet with the invite link, counted (`inviteShared`) when it's opened.
    @ViewBuilder
    private func inviteLink<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        let content = label()
        if let code = friends.code {
            ShareLink(
                item: InviteLink.shareURL(for: code),
                subject: Text("Lockin"),
                message: Text(InviteLink.shareMessage)
            ) {
                content
            }
            .simultaneousGesture(TapGesture().onEnded {
                friends.noteInviteShared()
            })
        }
    }

    // MARK: - Friends

    @ViewBuilder
    private var friendsContent: some View {
        if !friends.friends.isEmpty {
            friendsSection
        } else if friends.hasLoaded {
            emptySection
        } else if let problem = friends.problem {
            Section {
                VStack(spacing: LKSpacing.m) {
                    Text(problem.localizedDescription)
                        .foregroundStyle(LKColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await friends.refresh() }
                    }
                    .lkSecondaryButton()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LKSpacing.l)
            }
        } else {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LKSpacing.l)
            }
        }
    }

    private var friendsSection: some View {
        Section {
            ForEach(friends.friends) { person in
                FriendRow(friend: person)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            removing = person
                        } label: {
                            Label("Remove", systemImage: "person.badge.minus")
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            blocking = person
                        } label: {
                            Label("Block", systemImage: "hand.raised")
                        }
                        Button {
                            sheet = .report(person)
                        } label: {
                            Label("Report", systemImage: "exclamationmark.bubble")
                        }
                    }
            }
        } header: {
            Text("Friends")
        } footer: {
            Text("Squads arrive next")
        }
    }

    /// No friends yet: your Lockling waves, and the invite is the one big button.
    private var emptySection: some View {
        Section {
            VStack(spacing: LKSpacing.l) {
                LocklingHero(avatar: account.user?.avatar ?? .default, pose: .celebrating, size: 84)
                    .accessibilityHidden(true)
                Text("No friends yet")
                    .font(LKFont.headline)
                inviteLink {
                    Label("Invite friends", systemImage: "square.and.arrow.up")
                        .font(LKFont.headline)
                        .frame(maxWidth: .infinity)
                }
                .lkProminentButton()
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LKSpacing.l)
        } footer: {
            Text("Squads arrive next")
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// Your code, big enough to scan from across a desk.
struct QRCodeSheet: View {
    let code: FriendCode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: LKSpacing.xl) {
                Spacer(minLength: 0)
                QRCodeImage(text: code.url.absoluteString)
                    .padding(LKSpacing.xl)
                    .background(.white, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous)
                            .strokeBorder(LKColor.separator)
                    }
                    .frame(maxWidth: 300)
                Text(verbatim: FriendCode.spaced(code.code))
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .speechSpellsOutCharacters()
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LKSpacing.xl)
            .frame(maxWidth: .infinity)
            .navigationTitle("Your code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
