import API
import Creature
import DesignSystem
import Model
import Paywall
import Social
import SwiftUI

/// One squad: its pet, its streak and this week's leaderboard (M5), the invite (code, QR and
/// link), muting "locking in" alerts, and leaving. Pushed from the Friends screen, or shown in a
/// sheet from Home's squad picker and pet.
///
/// M7: a boosted squad's pet (someone in it has Lockin Plus) wears what any member picks; without
/// the boost, picking one opens the paywall (SPEC.md §2, paywall moment 3). The streak shows the
/// days freezes filled. A Review Squad has Demo Buddy, labelled "Test bot", and a button to ask
/// it to lock in.
struct SquadDetailScreen: View {
    @ObservedObject var squads: SquadsStore
    /// For counting invites shared (`inviteShared`), the same count as a friend invite.
    let friends: FriendsStore
    /// Squad Boost's paywall, and whether your freezes show (M7).
    @ObservedObject var plus: PlusStore
    /// Yours, for the paywall's header.
    let avatar: AvatarCode
    let squadID: String
    /// Your account's id, to tell whether the squad is yours to hand on.
    let myID: String?

    @State private var invite: FriendCode?
    @State private var inviteFailed = false
    @State private var muted: Bool
    @State private var showsQR = false
    @State private var confirmsLeave = false
    @State private var isLeaving = false
    @State private var failure: String? = nil
    @State private var showsPaywall = false
    /// Demo Buddy is being asked to lock in, or has been.
    @State private var buddy: BuddyRequest = .idle
    @Environment(\.dismiss) private var dismiss

    enum BuddyRequest: Equatable {
        case idle
        case asking
        case asked
    }

    /// - Parameter invite: the invite to show straight away (snapshots); otherwise it's fetched.
    init(
        squads: SquadsStore,
        friends: FriendsStore,
        plus: PlusStore,
        avatar: AvatarCode,
        squadID: String,
        myID: String?,
        invite: FriendCode? = nil
    ) {
        self.squads = squads
        self.friends = friends
        self.plus = plus
        self.avatar = avatar
        self.squadID = squadID
        self.myID = myID
        _invite = State(initialValue: invite)
        _muted = State(initialValue: squads.squads.first { $0.id == squadID }?.muted ?? false)
    }

    private var squad: Squad? {
        squads.squads.first { $0.id == squadID }
    }

    var body: some View {
        Group {
            if let squad {
                content(squad)
            } else {
                // Left, or gone from the list: nothing to show.
                ContentUnavailableView("Not in this squad", systemImage: "person.3")
            }
        }
        .navigationTitle(squad?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert("Something went wrong", message: $failure)
    }

    private func content(_ squad: Squad) -> some View {
        List {
            petSection(squad)
            accessorySection(squad)
            Section {
                SquadStreakRow(streak: squad.streak, timeZone: squad.timeZone, showsFreezes: plus.isPlus)
            } header: {
                Text("Streak")
            } footer: {
                if plus.isPlus {
                    Text("A streak freeze fills a day the squad missed, so the streak carries on. Lockin Plus gives you 2 a month.")
                }
            }
            if squad.hasBot {
                demoBuddySection(squad)
            }
            weekSection(squad)
            inviteSection(squad)
            Section {
                Toggle("Mute ‘locking in’ alerts", isOn: $muted)
            }
            Section {
                Button(role: .destructive) {
                    confirmsLeave = true
                } label: {
                    HStack {
                        Text("Leave squad")
                        if isLeaving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isLeaving)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await squads.refresh()
            if let fresh = squads.squad(id: squad.id) {
                await squads.loadLeaderboard(for: fresh)
            }
        }
        .onChange(of: squad.muted) { _, value in
            muted = value
        }
        .onChange(of: muted) { _, value in
            guard value != squad.muted else { return }
            Task {
                await squads.setMuted(squad, value)
            }
        }
        .confirmationDialog(
            Text("Leave \(squad.name)?"),
            isPresented: $confirmsLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                leave(squad)
            }
        } message: {
            Text(leaveMessage(squad))
        }
        .sheet(isPresented: $showsQR) {
            if let invite {
                QRCodeSheet(code: invite, title: "Squad code")
            }
        }
        .task {
            await squads.loadLeaderboard(for: squad)
        }
        .task {
            await loadInvite(squad)
        }
    }

    // MARK: - Pet, streak and the week (M5)

    /// The squad's pet, big, with its name, mood and growth.
    private func petSection(_ squad: Squad) -> some View {
        Section {
            SquadPetCard(pet: squad.pet, boosted: squad.boosted)
        } header: {
            if squad.openSessionId != nil {
                Label("Locked in now", systemImage: "lock.fill")
                    .foregroundStyle(LKColor.focusing)
            }
        }
    }

    /// Everyone's focused minutes since Monday, most first. Members show without their minutes
    /// until the week has loaded.
    private func weekSection(_ squad: Squad) -> some View {
        let ranking = squads.ranking(of: squad)
        return Section {
            ForEach(Array(ranking.enumerated()), id: \.element.member.id) { index, row in
                LeaderboardRow(place: index + 1, member: row.member, entry: row.entry, isMe: row.member.id == myID)
            }
        } header: {
            Text("This week")
        } footer: {
            Text("Starts again on Monday.")
        }
    }

    // MARK: - Squad Boost (M7)

    /// One row on the squad's page: what the pet wears, and a way to the accessories. Plus's
    /// crown when the squad has no boost. An egg has nothing to wear them on yet.
    @ViewBuilder
    private func accessorySection(_ squad: Squad) -> some View {
        if squad.pet.hasHatched {
            Section {
                NavigationLink {
                    List {
                        if let current = self.squad {
                            accessoryGrid(current)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("Dress up")
                    .navigationBarTitleDisplayMode(.inline)
                    // The accessories are the only way to the paywall here (moment 3), so it opens
                    // from their screen, the one on top.
                    .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: avatar)
                } label: {
                    LabeledContent {
                        if squad.boosted {
                            Text(squad.pet.wornAccessory?.title ?? "Nothing")
                        } else {
                            PlusBadge()
                        }
                    } label: {
                        Label("Dress up", systemImage: "tshirt.fill")
                    }
                }
            }
        } else if squad.boosted {
            Section {
                Label("Your pet can dress up once it hatches.", systemImage: "sparkles")
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
            }
        }
    }

    /// The pet's accessories: none and the six, each on the squad's pet. Without the boost each
    /// wears Plus's crown and opens the paywall.
    private func accessoryGrid(_ squad: Squad) -> some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LKSpacing.s), count: 4), spacing: LKSpacing.s) {
                AccessoryTile(
                    title: "None",
                    pet: dressed(squad.pet, in: nil),
                    isSelected: squad.pet.wornAccessory == nil,
                    isLocked: false
                ) {
                    choose(nil, in: squad)
                }
                ForEach(PetAccessory.allCases) { accessory in
                    AccessoryTile(
                        title: accessory.title,
                        pet: dressed(squad.pet, in: accessory),
                        isSelected: squad.pet.wornAccessory == accessory,
                        isLocked: !squad.boosted
                    ) {
                        choose(accessory, in: squad)
                    }
                }
            }
            .padding(.vertical, LKSpacing.s)
            .sensoryFeedback(.selection, trigger: squad.pet.accessory)
        } footer: {
            Text(squad.boosted
                ? "Anyone in the squad can pick. Everyone sees it, in the Live Activity too."
                : "Squad Boost: when anyone in the squad has Lockin Plus, your pet can dress up.")
        }
    }

    /// The squad's pet wearing `accessory`, for its tile.
    private func dressed(_ pet: SquadPet, in accessory: PetAccessory?) -> PetCode {
        PetCode(species: pet.code.species, stage: pet.code.stage, accessory: accessory?.rawValue)
    }

    /// A tile tapped: without the boost, the paywall; with it, the pet changes for everyone.
    private func choose(_ accessory: PetAccessory?, in squad: Squad) {
        guard squad.boosted else {
            if accessory != nil {
                showsPaywall = true
            }
            return
        }
        guard accessory?.rawValue != squad.pet.accessory else { return }
        Task {
            do {
                try await squads.setPetAccessory(squad, to: accessory?.rawValue)
            } catch is CancellationError {
                return
            } catch {
                if error.hitsFreeLimit {
                    // The boost lapsed since the list loaded.
                    showsPaywall = true
                } else {
                    failure = error.squadMessage
                }
            }
        }
    }

    // MARK: - Demo Buddy (docs/launch/app-review-notes.md §3)

    private func demoBuddySection(_ squad: Squad) -> some View {
        Section {
            Button {
                askDemoBuddy(squad)
            } label: {
                HStack {
                    Label("Ask Demo Buddy to lock in", systemImage: "lock.fill")
                    if buddy == .asking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(buddy == .asking)
        } header: {
            Text("Demo Buddy")
        } footer: {
            if buddy == .asked {
                Text("Demo Buddy is locking in for 3 minutes. Lock your phone to see its alert, then join from it or from Home.")
            } else {
                Text("Demo Buddy is a test bot. It locks in for 3 minutes, and the squad gets the usual alert.")
            }
        }
    }

    private func askDemoBuddy(_ squad: Squad) {
        guard buddy != .asking else { return }
        buddy = .asking
        Task {
            do {
                try await squads.askDemoBuddy(squad)
                buddy = .asked
            } catch is CancellationError {
                buddy = .idle
            } catch {
                buddy = .idle
                failure = error.squadMessage
            }
        }
    }

    // MARK: - Invite

    private func inviteSection(_ squad: Squad) -> some View {
        Section {
            HStack(spacing: LKSpacing.l) {
                Text(verbatim: FriendCode.spaced(invite?.code ?? "XXXXXXXX"))
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .speechSpellsOutCharacters()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                    .redacted(reason: invite == nil ? .placeholder : [])
                Spacer(minLength: 0)
                qrButton
            }
            .padding(.vertical, LKSpacing.xs)

            if let invite {
                ShareLink(
                    item: InviteLink.shareURL(for: invite),
                    subject: Text("Lockin"),
                    message: Text("Lock in with \(squad.name) on Lockin")
                ) {
                    Label("Invite to \(squad.name)", systemImage: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    friends.noteInviteShared()
                })
            } else if inviteFailed {
                Button {
                    Task { await loadInvite(squad) }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Invite")
        }
    }

    private var qrButton: some View {
        Button {
            showsQR = true
        } label: {
            Group {
                if let invite {
                    QRCodeImage(text: invite.url.absoluteString)
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
        .disabled(invite == nil)
        .accessibilityLabel("Show QR code")
    }

    // MARK: - Actions

    private func loadInvite(_ squad: Squad) async {
        guard invite == nil else { return }
        inviteFailed = false
        do {
            invite = try await squads.invite(squad)
        } catch is CancellationError {
            return
        } catch {
            inviteFailed = true
        }
    }

    private func leaveMessage(_ squad: Squad) -> String {
        if let myID, squad.ownerId == myID, squad.members.count > 1 {
            return "The squad passes to the next member. You'll need a new invite to come back."
        }
        return "You'll need a new invite to come back."
    }

    private func leave(_ squad: Squad) {
        isLeaving = true
        Task {
            defer { isLeaving = false }
            do {
                try await squads.leave(squad)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                failure = error.squadMessage
            }
        }
    }
}

/// One of the pet's accessories to pick: the squad's pet wearing it, and its name. Plus's crown
/// sits on it while the squad isn't boosted.
private struct AccessoryTile: View {
    let title: String
    let pet: PetCode
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: LKSpacing.xxs) {
                PetView(code: pet, mood: PetMood.happy.rawValue, size: 48)
                    .frame(width: 56, height: 56)
                    .overlay(alignment: .topTrailing) {
                        if isLocked {
                            PlusBadge(size: 18)
                        }
                    }
                Text(title)
                    .font(LKFont.caption.weight(.medium))
                    .foregroundStyle(LKColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, LKSpacing.s)
            .padding(.horizontal, LKSpacing.xxs)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? AnyShapeStyle(LKColor.tint.opacity(0.14)) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                in: shape
            )
            .overlay {
                shape.strokeBorder(isSelected ? AnyShapeStyle(LKColor.tint) : AnyShapeStyle(Color.clear), lineWidth: 2)
            }
            .contentShape(shape)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLocked ? Text("Lockin Plus") : Text(""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Squad {
    /// The squad's zone, which says when its days start (M5); this phone's from an older server.
    var timeZone: TimeZone {
        tz.flatMap(TimeZone.init(identifier:)) ?? .current
    }
}
