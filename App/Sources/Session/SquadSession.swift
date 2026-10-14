import Creature
import DesignSystem
import Model
import SwiftUI

// The session screen's squad parts: the squadmates' row, the cheer picker, and a cheer landing
// on your Lockling.

typealias RoomMember = LockinAttributes.ContentState.Member
typealias RoomCheer = LockinAttributes.ContentState.Cheer

/// A squad session as the session screen shows it. Plain values rather than the engine, so
/// snapshots can show a room the preview engine can't hold.
struct SquadSessionInfo: Equatable {
    /// The squad's name, when the squads list has it.
    var name: String?
    /// The room's latest state: everyone's timer, the pet, the latest cheer.
    var room: LockinAttributes.ContentState
    /// Your member id in `room`.
    var me: String

    /// Everyone but you, in the room's order (host first).
    var others: [RoomMember] {
        room.m.filter { $0.i != me }
    }

    /// The latest cheer, when it's for you.
    var cheerForMe: RoomCheer? {
        guard let cheer = room.c, cheer.t == me else { return nil }
        return cheer
    }

    func member(id: String) -> RoomMember? {
        room.member(id: id)
    }
}

/// The eight cheers (`Cheer.k`, 0–7 on the server): SF Symbols, each in its own system colour.
/// The order is the wire format: never reorder, only add at the end.
enum CheerKind: Int, CaseIterable, Identifiable, Sendable {
    case applause = 0
    case fire = 1
    case star = 2
    case heart = 3
    case lightning = 4
    case thumbsUp = 5
    case party = 6
    case sparkles = 7

    /// A kind from a newer app shows as sparkles rather than nothing.
    init(kind: Int) {
        self = CheerKind(rawValue: kind) ?? .sparkles
    }

    var id: Int { rawValue }

    /// All exist on iOS 17 and later.
    var symbol: String {
        switch self {
        case .applause: "hands.clap.fill"
        case .fire: "flame.fill"
        case .star: "star.fill"
        case .heart: "heart.fill"
        case .lightning: "bolt.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .party: "party.popper.fill"
        case .sparkles: "sparkles"
        }
    }

    var colour: Color {
        switch self {
        case .applause: .orange
        case .fire: .red
        case .star: .yellow
        case .heart: .pink
        case .lightning: .cyan
        case .thumbsUp: .indigo
        case .party: .purple
        case .sparkles: .mint
        }
    }

    /// For VoiceOver.
    var name: LocalizedStringKey {
        switch self {
        case .applause: "Applause"
        case .fire: "Fire"
        case .star: "Star"
        case .heart: "Heart"
        case .lightning: "Lightning"
        case .thumbsUp: "Thumbs up"
        case .party: "Party"
        case .sparkles: "Sparkles"
        }
    }
}

// MARK: - Squadmates

/// Everyone else in the room, side by side: their Lockling in the pose for their state, their
/// name, and their countdown (or Done, Left). Tap one to cheer them on.
struct SquadmatesRow: View {
    let members: [RoomMember]
    /// The room's latest cheer: its symbol shows on whoever got it, until the server clears it.
    let cheer: RoomCheer?
    /// Whose cheer picker is open.
    let selection: String?
    let onSelect: (RoomMember) -> Void

    var body: some View {
        if members.isEmpty {
            // Just you so far. The server has told the squad you're locking in.
            Label("Your squad's been told", systemImage: "bell.fill")
                .font(LKFont.footnote.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 54)
        } else {
            HStack(alignment: .top, spacing: LKSpacing.xs) {
                ForEach(members, id: \.i) { member in
                    Button {
                        onSelect(member)
                    } label: {
                        SquadmateCell(
                            member: member,
                            cheer: cheer?.t == member.i ? cheer : nil,
                            isSelected: selection == member.i
                        )
                    }
                    .buttonStyle(TileButtonStyle())
                    // No cheering someone who's gone.
                    .disabled(member.state == .left)
                    .frame(maxWidth: 84)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SquadmateCell: View {
    let member: RoomMember
    /// A cheer they've just been sent.
    let cheer: RoomCheer?
    let isSelected: Bool

    private var tone: LKMemberTone {
        LKMemberTone(rawValue: member.state.rawValue) ?? .left
    }

    var body: some View {
        VStack(spacing: LKSpacing.xs) {
            CreatureView(avatar: member.avatar, pose: CreaturePose(member.state), size: 40)
                .frame(width: 54, height: 54)
                .background(
                    CreatureCatalogue.colour(member.avatar.colour).opacity(isSelected ? 0.3 : 0.16),
                    in: Circle()
                )
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(LKColor.tint, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let cheer {
                        CheerBadge(kind: CheerKind(kind: cheer.k))
                            .offset(x: 6, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Text(member.n)
                .font(LKFont.caption.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
            status
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: member.n))
        .accessibilityValue(Text(tone.title))
        .accessibilityHint(member.state == .left ? Text("") : Text("Cheer them on"))
    }

    /// Their countdown while they're in it (frozen while paused); otherwise how it ended.
    @ViewBuilder
    private var status: some View {
        switch member.state {
        case .focusing, .onBreak, .paused:
            Text(timerInterval: member.timerRange, pauseTime: member.state == .paused ? member.pausedDate : nil, countsDown: true)
                .font(LKFont.timerSquadmate)
                .foregroundStyle(tone.color)
                .multilineTextAlignment(.center)
        case .done, .left, .slipped:
            Text(tone.title)
                .font(LKFont.subheadline.weight(.semibold))
                .foregroundStyle(tone.color)
        }
    }
}

/// A cheer's symbol on a small disc, pinned to whoever got it.
private struct CheerBadge: View {
    let kind: CheerKind

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(kind.colour)
            .frame(width: 24, height: 24)
            .background(.regularMaterial, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Cheer picker

/// Where the squadmates' row sits, so the cheer picker can open just under it.
struct SquadRowBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The cheer picker, floating under the squadmates' row over the rest of the screen. A tap
/// anywhere else closes it.
struct CheerPickerLayer: View {
    let rowBounds: Anchor<CGRect>?
    /// Whose picker is open; nil when it's closed.
    let member: RoomMember?
    let onCheer: (CheerKind, RoomMember) -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            if let member {
                let top = rowBounds.map { proxy[$0].maxY } ?? 0
                ZStack(alignment: .top) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onClose)
                        .accessibilityHidden(true)
                    CheerPicker(name: member.n) { kind in
                        onCheer(kind, member)
                    }
                    .padding(.top, top + LKSpacing.s)
                    .padding(.horizontal, LKSpacing.xl)
                    .accessibilityAction(.escape, onClose)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .allowsHitTesting(member != nil)
    }
}

/// "Cheer Ava on", and the eight cheers in two rows of four.
struct CheerPicker: View {
    let name: String
    let onCheer: (CheerKind) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: LKSpacing.s), count: 4)

    var body: some View {
        VStack(spacing: LKSpacing.m) {
            Text("Cheer \(name) on")
                .font(LKFont.subheadline.weight(.semibold))
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
            LazyVGrid(columns: Self.columns, spacing: LKSpacing.s) {
                ForEach(CheerKind.allCases) { kind in
                    Button {
                        onCheer(kind)
                    } label: {
                        Image(systemName: kind.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(kind.colour)
                            .frame(width: 56, height: 56)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityLabel(Text(kind.name))
                }
            }
        }
        .padding(LKSpacing.l)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - A cheer for you

/// A cheer landing on your Lockling: the symbol pops in with who sent it, and drifts up as it
/// fades. Reduce Motion keeps it still.
struct FloatingCheer: View {
    let kind: CheerKind
    let from: String?

    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: LKSpacing.xxs) {
            Image(systemName: kind.symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(kind.colour)
                .symbolEffect(.bounce, value: risen)
            if let from {
                Text(verbatim: from)
                    .font(LKFont.caption.weight(.semibold))
                    .foregroundStyle(LKColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, LKSpacing.m)
        .padding(.vertical, LKSpacing.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LKRadius.medium, style: .continuous))
        .offset(y: risen && !reduceMotion ? -28 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 2.2)) {
                risen = true
            }
        }
        .accessibilityHidden(true)
    }
}
