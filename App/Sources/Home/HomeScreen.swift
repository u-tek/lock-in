import API
import Creature
import DesignSystem
import Model
import Paywall
import SessionEngine
import Social
import SwiftUI

/// Home: your Lockling, how long, and one button. Coins, Plus and Settings sit in a row across
/// the top; friends are a quiet row at the bottom. Once you're in a squad, a row of chips above
/// the lengths picks who to lock in with: solo or a squad.
struct HomeScreen: View {
    enum Sheet: Identifiable, Equatable {
        case paywall
        case settings
        case friends
        case customLength
        /// A squad's page, from a long press on its chip or a tap on its pet.
        case squad(String)
        /// The coin shop, from the coin count (M5).
        case shop

        var id: String {
            switch self {
            case .paywall: "paywall"
            case .settings: "settings"
            case .friends: "friends"
            case .customLength: "customLength"
            case .squad(let id): "squad.\(id)"
            case .shop: "shop"
            }
        }
    }

    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore
    @ObservedObject var friends: FriendsStore
    @ObservedObject var account: AccountStore
    @ObservedObject var squads: SquadsStore
    /// Coins and the shop (M5).
    @ObservedObject var shop: ShopStore
    let social: SocialModels
    /// Alerts: a tap on "is locking in" picks its squad here (M4).
    @ObservedObject private var alerts: NotificationInbox = AppServices.notificationInbox

    @State private var minutes: Int
    /// The squad chosen in the picker; nil for solo.
    @State private var squadChoice: String?
    @State private var sheet: Sheet?
    @State private var pokes = 0
    @State private var lockIns = 0
    /// A squad session is being joined or opened on the server.
    @State private var isStarting = false
    @State private var failure: String? = nil

    /// - Parameter squadID: the squad chosen to start with (snapshots); solo otherwise.
    init(
        engine: SessionEngine,
        plus: PlusStore,
        social: SocialModels,
        minutes: Int = SessionPreset.twentyFive.minutes,
        squadID: String? = nil
    ) {
        self.engine = engine
        self.plus = plus
        self.friends = social.friends
        self.account = social.account
        self.squads = social.squads
        self.shop = social.shop
        self.social = social
        _minutes = State(initialValue: minutes)
        _squadChoice = State(initialValue: squadID)
    }

    /// Your squads, once you're signed in with a handle. Signed out there are none to show, even
    /// if the last account's are still in memory.
    private var mySquads: [Squad] {
        account.state.isSignedIn ? squads.squads : []
    }

    /// The chosen squad, while you're still in it.
    private var chosenSquad: Squad? {
        guard let squadChoice else { return nil }
        return mySquads.first { $0.id == squadChoice }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: LKSpacing.s)
                    hero(height: proxy.size.height)
                    if let squad = chosenSquad {
                        // A squad picked: its pet and its streak instead of yours (M5).
                        SquadPetChips(squad: squad) {
                            sheet = .squad(squad.id)
                        }
                        .padding(.top, LKSpacing.l)
                    } else {
                        StatChips(stats: engine.stats)
                            .padding(.top, LKSpacing.l)
                    }
                        .padding(.top, LKSpacing.l)
                    Spacer(minLength: LKSpacing.l)
                    if !mySquads.isEmpty {
                        SquadPicker(squads: mySquads, rooms: social.rooms, selection: $squadChoice) { squad in
                            sheet = .squad(squad.id)
                        }
                        .padding(.bottom, LKSpacing.m)
                    }
                    DurationPicker(minutes: $minutes, isPlus: plus.isPlus) {
                        sheet = plus.isPlus ? .customLength : .paywall
                    }
                    lockInButton
                        .padding(.top, LKSpacing.l)
                    friendsButton
                        .padding(.top, LKSpacing.xs)
                }
                .padding(.horizontal, LKSpacing.xl)
                .padding(.bottom, LKSpacing.xs)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Color(uiColor: .systemBackground))
            // The row is part of the screen, not a navigation bar: iOS 26 bars shrink custom items
            // to icons, which dropped the coin count and the word "Plus".
            .toolbar(.hidden, for: .navigationBar)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .paywall:
                PaywallView(store: plus, avatar: engine.avatar) {
                    self.sheet = nil
                }
            case .settings:
                SettingsScreen(engine: engine, plus: plus, social: social) {
                    self.sheet = nil
                }
            case .friends:
                FriendsFlow(social: social, plus: plus, avatar: engine.avatar)
            case .customLength:
                CustomLengthSheet(minutes: $minutes)
            case .squad(let id):
                NavigationStack {
                    SquadDetailScreen(squads: squads, friends: friends, squadID: id, myID: account.user?.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { self.sheet = nil }
                            }
                        }
                }
            }
        }
        .errorAlert("Couldn't lock in", message: $failure)
        // An invite link opens Friends, once no session covers Home.
        .onChange(of: friends.pendingInviteCode, initial: true) {
            openPendingInvite()
        }
        .onChange(of: engine.phase) {
            openPendingInvite()
        }
        // A tap on an "is locking in" alert: its squad, picked, with "Join in" waiting.
        .onChange(of: alerts.squadRequest, initial: true) { _, request in
            pick(request)
        }
    }

    private func pick(_ request: NotificationInbox.SquadRequest?) {
        guard let request else { return }
        squadChoice = request.squadId
        sheet = nil
        alerts.squadRequest = nil
    }

    private func openPendingInvite() {
        guard friends.pendingInviteCode != nil, engine.phase == .idle, sheet != .friends else { return }
        sheet = .friends
    }

    /// The Lockling, as large as the screen allows: 200 points on most phones, less on an SE, and
    /// a little less again when the squad chips need the room.
    private func hero(height: CGFloat) -> some View {
        LocklingHero(
            avatar: engine.avatar,
            pose: .idle,
            size: min(200, max(110, height * (mySquads.isEmpty ? 0.3 : 0.26))),
            backdrop: .halo
        )
        .bump(on: pokes)
        .onTapGesture { pokes += 1 }
        .sensoryFeedback(.impact(weight: .light), trigger: pokes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Lockling")
    }

    private var lockInButton: some View {
        Button(action: lockIn) {
            ZStack {
                Label(lockInTitle, systemImage: "lock.fill")
                    .opacity(isStarting ? 0 : 1)
                if isStarting {
                    ProgressView()
                }
            }
            .font(LKFont.headline)
            .frame(maxWidth: .infinity)
        }
        .lkProminentButton()
        .controlSize(.large)
        .disabled(isStarting)
        .sensoryFeedback(.impact(weight: .medium), trigger: lockIns)
    }

    /// "Join in" when the chosen squad's room is already open.
    private var lockInTitle: LocalizedStringKey {
        chosenSquad?.openSessionId != nil ? "Join in" : "Lock in"
    }

    /// Solo starts at once. A squad goes through the server first: it joins the squad's open
    /// room, or opens one and tells the squad.
    private func lockIn() {
        lockIns += 1
        guard let squad = chosenSquad else {
            engine.start(minutes: minutes)
            return
        }
        guard !isStarting else { return }
        isStarting = true
        let minutes = self.minutes
        Task {
            defer { isStarting = false }
            do {
                try await engine.startSquad(squadId: squad.id, minutes: minutes)
            } catch is CancellationError {
                return
            } catch {
                if error.hitsFreeLimit {
                    sheet = .paywall
                } else {
                    failure = error.squadMessage
                }
            }
        }
    }

    private var friendsTitle: LocalizedStringKey {
        mySquads.isEmpty ? "Lock in with friends" : "Squads and friends"
    }

    private var friendsButton: some View {
        Button {
            sheet = .friends
        } label: {
            Label(friendsTitle, systemImage: "person.2.fill")
                .font(LKFont.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
    }

    private var topBar: some View {
        HStack(spacing: LKSpacing.s) {
            CoinCount(coins: engine.stats.coins)
                .padding(.horizontal, LKSpacing.m)
                .frame(minHeight: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            Spacer()
            if !plus.isPlus {
                Button {
                    sheet = .paywall
                } label: {
                    Label {
                        Text("Plus")
                    } icon: {
                        Image(systemName: LockinSymbol.plus)
                            .foregroundStyle(LockinColour.plus)
                    }
                    .font(LKFont.subheadline.weight(.semibold))
                    .padding(.horizontal, LKSpacing.m)
                    .frame(minHeight: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lockin Plus")
            }
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(LKFont.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, LKSpacing.s)
    }
}

/// Today's minutes and the streak, as two small capsules.
private struct StatChips: View {
    let stats: FocusStats

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            StatChip(symbol: "clock.fill", colour: LKColor.tint, text: "\(stats.todayMinutes) min today")
            StatChip(symbol: "flame.fill", colour: .orange, text: streak)
        }
    }

    private var streak: String {
        switch stats.streakDays {
        case 0: "No streak yet"
        case 1: "1 day"
        default: "\(stats.streakDays) days"
        }
    }
}

private struct StatChip: View {
    let symbol: String
    let colour: Color
    let text: String

    var body: some View {
        Label {
            Text(text)
                .monospacedDigit()
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(colour)
        }
        .font(LKFont.subheadline.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, LKSpacing.m)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

/// 25, 50 and 90 minutes, and a custom length (Lockin Plus): four big tiles.
private struct DurationPicker: View {
    @Binding var minutes: Int
    let isPlus: Bool
    let onCustom: () -> Void

    private let presets = SessionPreset.standard.map(\.minutes)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.self) { value in
                DurationTile(isSelected: minutes == value) {
                    withAnimation(.snappy) { minutes = value }
                } content: {
                    Text(value, format: .number)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("min")
                        .font(LKFont.caption.weight(.medium))
                }
                .accessibilityLabel("\(value) minutes")
            }
            customTile
        }
        .sensoryFeedback(.selection, trigger: minutes)
    }

    private var customTile: some View {
        let isCustom = !presets.contains(minutes)
        return DurationTile(isSelected: isCustom, action: onCustom) {
            if isCustom {
                Text(minutes, format: .number)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("min")
                    .font(LKFont.caption.weight(.medium))
            } else {
                Image(systemName: isPlus ? "timer" : LockinSymbol.plus)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isPlus ? AnyShapeStyle(.primary) : AnyShapeStyle(LockinColour.plus))
                    .frame(height: 28)
                Text("Custom")
                    .font(LKFont.caption.weight(.medium))
            }
        }
        .accessibilityLabel(isCustom ? "\(minutes) minutes" : "Custom length")
        .accessibilityValue(isPlus ? Text("") : Text("Lockin Plus"))
    }
}

private struct DurationTile<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                content
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                isSelected ? AnyShapeStyle(LKColor.tint) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lockin Plus: any length from 5 minutes to the 4-hour cap.
private struct CustomLengthSheet: View {
    @Binding var minutes: Int
    @State private var draft: Int
    @Environment(\.dismiss) private var dismiss

    private static let choices = Array(stride(from: 5, through: SessionPreset.customRange.upperBound, by: 5))

    init(minutes: Binding<Int>) {
        _minutes = minutes
        _draft = State(initialValue: minutes.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Picker("Minutes", selection: $draft) {
                ForEach(Self.choices, id: \.self) { value in
                    Text("\(value) min").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle("Custom length")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        minutes = draft
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
