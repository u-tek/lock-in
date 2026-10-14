import API
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

/// One squad: its pet, its streak and this week's leaderboard (M5), the invite (code, QR and
/// link), muting "locking in" alerts, and leaving. Pushed from the Friends screen, or shown in a
/// sheet from Home's squad picker and pet.
struct SquadDetailScreen: View {
    @ObservedObject var squads: SquadsStore
    /// For counting invites shared (`inviteShared`), the same count as a friend invite.
    let friends: FriendsStore
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
    @Environment(\.dismiss) private var dismiss

    /// - Parameter invite: the invite to show straight away (snapshots); otherwise it's fetched.
    init(squads: SquadsStore, friends: FriendsStore, squadID: String, myID: String?, invite: FriendCode? = nil) {
        self.squads = squads
        self.friends = friends
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
            Section {
                SquadStreakRow(streak: squad.streak)
            } header: {
                Text("Streak")
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
            SquadPetCard(pet: squad.pet)
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
