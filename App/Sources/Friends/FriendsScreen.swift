import API
import Creature
import DesignSystem
import Model
import Paywall
import Social
import SwiftUI

/// Squads first (each one's Locklings, and a new one or one to join), then your friend code (big,
/// as a QR code, and as a link to share), a way to add a friend by theirs, and your friends.
struct FriendsScreen: View {
    enum Sheet: Identifiable {
        case addFriend
        case joinSquad
        /// An invite link's code, redeemed straight away as a squad or a friend.
        case invite(code: String)
        case newSquad
        case qr(FriendCode)
        case report(Friend)
        /// One squad too many on the free plan (SPEC.md §2, paywall moment 2).
        case paywall

        var id: String {
            switch self {
            case .addFriend: "addFriend"
            case .joinSquad: "joinSquad"
            case .invite(let code): "invite.\(code)"
            case .newSquad: "newSquad"
            case .qr: "qr"
            case .report(let person): "report.\(person.id)"
            case .paywall: "paywall"
            }
        }
    }

    /// A squad's page, pushed onto this screen's stack.
    struct SquadLink: Hashable {
        let id: String
    }

    /// Squads you can be in: one free, three with Plus (SPEC.md §2).
    static let freeSquads = 1
    static let plusSquads = 3

    @ObservedObject var account: AccountStore
    @ObservedObject var friends: FriendsStore
    @ObservedObject var squads: SquadsStore
    @ObservedObject var plus: PlusStore
    /// Yours: the new squad's picture and the paywall's header.
    let avatar: AvatarCode
    let onDone: () -> Void

    @State private var path: [SquadLink]
    @State private var sheet: Sheet? = nil
    @State private var removing: Friend? = nil
    @State private var blocking: Friend? = nil
    @State private var failure: String? = nil

    /// - Parameters:
    ///   - sheet: a sheet to show straight away (snapshots).
    ///   - squadID: a squad's page to open straight away (snapshots).
    init(
        social: SocialModels,
        plus: PlusStore,
        avatar: AvatarCode,
        sheet: Sheet? = nil,
        squadID: String? = nil,
        onDone: @escaping () -> Void
    ) {
        account = social.account
        friends = social.friends
        squads = social.squads
        self.plus = plus
        self.avatar = avatar
        self.onDone = onDone
        _sheet = State(initialValue: sheet)
        _path = State(initialValue: squadID.map { [SquadLink(id: $0)] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                squadsSection
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
                await refresh()
            }
            .navigationDestination(for: SquadLink.self) { link in
                SquadDetailScreen(squads: squads, friends: friends, squadID: link.id, myID: account.user?.id)
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
            case .addFriend:
                AddFriendSheet(friends: friends, squads: squads, plus: plus, avatar: avatar, purpose: .friend)
            case .joinSquad:
                AddFriendSheet(friends: friends, squads: squads, plus: plus, avatar: avatar, purpose: .squad)
            case .invite(let code):
                AddFriendSheet(friends: friends, squads: squads, plus: plus, avatar: avatar, purpose: .link, code: code, submitsAtOnce: true)
            case .newSquad:
                NewSquadSheet(squads: squads, plus: plus, avatar: avatar) { squad in
                    path = [SquadLink(id: squad.id)]
                }
            case .qr(let code):
                QRCodeSheet(code: code)
            case .report(let person):
                ReportSheet(friends: friends, person: person)
            case .paywall:
                PaywallView(store: plus, avatar: avatar) {
                    self.sheet = nil
                }
            }
        }
        .errorAlert("Something went wrong", message: $failure)
        .task {
            await refresh()
        }
        // An invite link opened while signed in (or just after signing in): a squad to join or a
        // friend to add, whichever the code is.
        .onChange(of: friends.pendingInviteCode, initial: true) {
            if let code = friends.takePendingInvite() {
                sheet = .invite(code: code)
            }
        }
    }

    private func refresh() async {
        await squads.refresh()
        await friends.refresh()
    }

    // MARK: - Squads

    private var squadsSection: some View {
        Section {
            ForEach(squads.squads) { squad in
                NavigationLink(value: SquadLink(id: squad.id)) {
                    SquadRow(squad: squad)
                }
            }
            if !isAtPlusLimit {
                Button(action: newSquad) {
                    HStack {
                        Label("New squad", systemImage: "plus.circle")
                        if needsPlusForNewSquad {
                            Spacer()
                            PlusBadge()
                        }
                    }
                }
                .accessibilityValue(needsPlusForNewSquad ? Text("Lockin Plus") : Text(""))
            }
            Button {
                sheet = .joinSquad
            } label: {
                Label("Join a squad", systemImage: "ticket")
            }
        } header: {
            Text("Squads")
        } footer: {
            if squads.squads.isEmpty {
                Text(squads.problem ?? "See each other in your Dynamic Island.")
            } else if isAtPlusLimit {
                Text("Up to \(Self.plusSquads) squads")
            }
        }
    }

    /// Free, and already in a squad: a second one is Plus.
    private var needsPlusForNewSquad: Bool {
        !plus.isPlus && squads.squads.count >= Self.freeSquads
    }

    private var isAtPlusLimit: Bool {
        plus.isPlus && squads.squads.count >= Self.plusSquads
    }

    private func newSquad() {
        sheet = needsPlusForNewSquad ? .paywall : .newSquad
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
                sheet = .addFriend
            } label: {
                Label("Add a friend", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Your friend code")
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

/// A friend or squad code, big enough to scan from across a desk.
struct QRCodeSheet: View {
    let code: FriendCode
    var title: LocalizedStringKey = "Your code"
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
