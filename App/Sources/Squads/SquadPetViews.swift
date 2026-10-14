import API
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

// The squad pet, its streak and the week's leaderboard in the app (docs/milestones/M5.md): the
// squad page's top sections, Home's pet chip, and the finished screen's XP line and hatch. The pet
// is drawn by the Creature module's `PetView`, the same one the Live Activity and the widgets use.

extension SquadPet {
    /// What to call it: "Egg" until it hatches (the egg's colour hints at its species, but the app
    /// names it only once it's out), then its stage and species, "Teen sprout". English only until
    /// the app has a string catalogue.
    var displayName: String {
        PetNames.name(code)
    }
}

enum PetNames {
    /// "Egg", "Baby puff", "Teen sprout", "Adult ember", "Prestige pebble".
    static func name(_ code: PetCode) -> String {
        guard code.growth != .egg else { return "Egg" }
        let species = PetSpecies(name: code.species).title.lowercased()
        let stage = code.stageName
        return "\(stage.prefix(1).uppercased())\(stage.dropFirst()) \(species)"
    }

    /// "Happy — the squad focused today".
    static func moodLine(_ mood: PetMood) -> String {
        switch mood {
        case .sad: "Sad — someone left a session early"
        case .hungry: "Hungry — nobody's focused today"
        case .content: "Content — a few more and today counts"
        case .happy: "Happy — the squad focused today"
        }
    }
}

// MARK: - Squad page

/// The squad page's first section: the pet, big, its name and mood, and how far it is from its
/// next stage. A boosted squad's (M7) wears its accessory and a "Boosted" badge.
struct SquadPetCard: View {
    let pet: SquadPet
    /// Squad Boost: someone in the squad has Lockin Plus.
    var boosted = false

    var body: some View {
        let mood = pet.petMood
        VStack(spacing: LKSpacing.m) {
            PetView(code: pet.code, mood: pet.mood, size: 120)
                .frame(width: 156, height: 156)
                .background(Circle().fill(LKColor.petMood(mood.rawValue).opacity(0.14)))
            VStack(spacing: LKSpacing.xxs) {
                Text(pet.displayName)
                    .font(LKFont.title2.weight(.bold))
                Text(PetNames.moodLine(mood))
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
                if boosted {
                    BoostedBadge()
                        .padding(.top, LKSpacing.xs)
                }
            }
            growth
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LKSpacing.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var growth: some View {
        if !pet.hasHatched {
            Text("Hatches when two of you finish a session together.")
                .font(LKFont.footnote)
                .foregroundStyle(LKColor.textSecondary)
                .multilineTextAlignment(.center)
        } else if let toGo = pet.xpToNextStage {
            VStack(spacing: LKSpacing.xs) {
                ProgressView(value: pet.clampedProgress)
                    .tint(LKColor.petMood(pet.petMood.rawValue))
                HStack {
                    Text("\(pet.xp, format: .number) XP")
                    Spacer()
                    Text("\(toGo, format: .number) to \(nextStage)")
                }
                .font(LKFont.footnote)
                .foregroundStyle(LKColor.textSecondary)
                .monospacedDigit()
            }
            .padding(.horizontal, LKSpacing.s)
        } else {
            Text("Fully grown · \(pet.xp, format: .number) XP")
                .font(LKFont.footnote)
                .foregroundStyle(LKColor.textSecondary)
                .monospacedDigit()
        }
    }

    /// "teen", "adult", "prestige": the stage after this one.
    private var nextStage: String {
        PetCode(species: pet.code.species, stage: pet.stage + 1).stageName
    }
}

/// "Boosted": Squad Boost is on (M7), because someone in the squad has Lockin Plus.
struct BoostedBadge: View {
    var body: some View {
        Label("Boosted", systemImage: "sparkles")
            .font(LKFont.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, LKSpacing.s)
            .padding(.vertical, 3)
            .background(LockinColour.plus.gradient, in: Capsule())
            .accessibilityLabel("Squad Boost on")
    }
}

/// The squad's streak: a flame, the days, and how many have counted today; under it the last
/// seven days, with the days a streak freeze filled (M7), and your freezes left when you have Plus.
struct SquadStreakRow: View {
    let streak: SquadStreak
    /// The squad's zone, which says what today is.
    var timeZone: TimeZone = .current
    /// You have Lockin Plus: your freezes left this month show.
    var showsFreezes = false
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            summary
            StreakWeek(days: streak.days(endingOn: SquadStreak.day(of: now, in: timeZone)))
            if showsFreezes {
                Label {
                    Text(freezesLeft)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "snowflake")
                        .foregroundStyle(.cyan)
                }
                .font(LKFont.footnote)
                .foregroundStyle(LKColor.textSecondary)
            }
        }
        .padding(.vertical, LKSpacing.xxs)
    }

    private var freezesLeft: String {
        streak.freezes == 1 ? "1 freeze left this month" : "\(max(0, streak.freezes)) freezes left this month"
    }

    private var summary: some View {
        HStack(spacing: LKSpacing.m) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(streak.count > 0 ? Color.orange : Color.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(days)
                    .font(LKFont.headline)
                Text("\(min(streak.doneToday, streak.needed)) of \(streak.needed) today")
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
            }
            .monospacedDigit()
            Spacer(minLength: 0)
            if streak.countedToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(LKColor.done)
                    .accessibilityLabel("Today counts")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var days: String {
        switch streak.count {
        case 0: "No streak yet"
        case 1: "1-day streak"
        default: "\(streak.count)-day streak"
        }
    }
}

/// The last seven days, oldest first: a flame on each day the streak counted, a snowflake where a
/// freeze filled one, a ring for today until it counts.
private struct StreakWeek: View {
    let days: [SquadStreak.Day]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: LKSpacing.xs) {
                    Text(Self.initial(day.weekday))
                        .font(LKFont.caption.weight(.medium))
                        .foregroundStyle(LKColor.textSecondary)
                    DayMark(mark: day.mark)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Self.spoken(day)))
            }
        }
    }

    private static let calendar = Calendar(identifier: .gregorian)

    /// "M" for Monday, in the phone's language.
    private static func initial(_ weekday: Int) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    /// "Monday, frozen". English only until the app has a string catalogue.
    private static func spoken(_ day: SquadStreak.Day) -> String {
        let symbols = calendar.weekdaySymbols
        let name = symbols.indices.contains(day.weekday - 1) ? symbols[day.weekday - 1] : day.day
        switch day.mark {
        case .counted: return "\(name), counted"
        case .frozen: return "\(name), saved by a streak freeze"
        case .pending: return "\(name), today, not counted yet"
        case .missed: return "\(name), not counted"
        }
    }
}

/// One day's mark in the week.
private struct DayMark: View {
    let mark: SquadStreak.Day.Mark

    private static let size: CGFloat = 28

    var body: some View {
        switch mark {
        case .counted:
            symbol("flame.fill", on: .orange)
        case .frozen:
            symbol("snowflake", on: .cyan)
        case .pending:
            Circle()
                .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: Self.size, height: Self.size)
        case .missed:
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: Self.size, height: Self.size)
        }
    }

    private func symbol(_ name: String, on colour: Color) -> some View {
        Image(systemName: name)
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(colour.gradient, in: Circle())
    }
}

/// "Test bot", beside Demo Buddy's name wherever squad members are listed
/// (docs/launch/app-review-notes.md §3).
struct TestBotLabel: View {
    var body: some View {
        Text("Test bot")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(LKColor.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .fixedSize()
    }
}

/// One member's week: their place, their Lockling, their name and their minutes. Minutes show as
/// a placeholder until the leaderboard has loaded. Demo Buddy, the test bot, is labelled as one and
/// has no minutes: it's never on a leaderboard.
struct LeaderboardRow: View {
    let place: Int
    let member: SquadMember
    let entry: Leaderboard.Entry?
    let isMe: Bool

    var body: some View {
        HStack(spacing: LKSpacing.m) {
            Text(verbatim: entry == nil ? " " : String(place))
                .font(LKFont.subheadline.weight(.semibold))
                .foregroundStyle(LKColor.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 18, alignment: .center)
            FriendAvatar(avatar: member.locklingAvatar, size: 40)
            Text(member.nameForDisplay)
                .font(LKFont.body.weight(isMe ? .semibold : .regular))
                .lineLimit(1)
            if member.isBot {
                TestBotLabel()
            }
            Spacer(minLength: LKSpacing.s)
            if !member.isBot {
                Text("\(entry?.minutes ?? 0, format: .number) min")
                    .font(LKFont.body)
                    .foregroundStyle(LKColor.textSecondary)
                    .monospacedDigit()
                    .redacted(reason: entry == nil ? .placeholder : [])
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Home

/// Home with a squad picked: the squad's pet and its streak, where your own minutes and streak sit
/// when solo. A tap opens the squad's page.
struct SquadPetChips: View {
    let squad: Squad
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: LKSpacing.s) {
                HStack(spacing: LKSpacing.xs + 2) {
                    PetView(code: squad.pet.code, mood: squad.pet.mood, size: 26)
                    Text(squad.pet.displayName)
                }
                .padding(.leading, LKSpacing.xs + 2)
                .padding(.trailing, LKSpacing.m)
                .padding(.vertical, 3)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                Label {
                    Text(streakText)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(squad.streak.count > 0 ? Color.orange : Color.secondary)
                }
                .padding(.horizontal, LKSpacing.m)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
            .font(LKFont.subheadline.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(.primary)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityHint("Opens the squad")
    }

    private var streakText: String {
        switch squad.streak.count {
        case 0: "No streak yet"
        case 1: "1 day"
        default: "\(squad.streak.count) days"
        }
    }

    private var accessibilityText: String {
        let streak = squad.streak.count == 0 ? "no streak yet" : "\(squad.streak.count)-day streak"
        return "\(squad.name)'s pet, \(squad.pet.displayName), \(squad.pet.petMood.name); \(streak)"
    }
}

// MARK: - Finished

/// What a finished squad session did for the squad's pet (M5): the XP it added and, when the egg
/// hatched during it, the hatch.
struct SquadPetResult: Equatable {
    let squadName: String
    /// Your whole focused minutes: what the room adds to the squad's XP.
    let xp: Int
    /// The pet now, from the room's last state (or the squads list when the room didn't say).
    let pet: PetCode?
    let mood: Int
    /// It was an egg when this session began and isn't now.
    let hatched: Bool
}

/// "+25 XP for Library Goblins", with the pet beside it.
struct SquadXPLine: View {
    let result: SquadPetResult

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            if let pet = result.pet {
                PetView(code: pet, mood: result.mood, size: 24)
            }
            Text("+\(result.xp, format: .number) XP for \(result.squadName)")
                .monospacedDigit()
        }
        .font(LKFont.headline)
        .foregroundStyle(LKColor.textSecondary)
    }
}

/// The egg hatching: it sits a moment, then the baby pops out of it. Snapshots show it out
/// already; with Reduce Motion it just appears.
struct HatchMoment: View {
    let pet: PetCode
    let mood: Int
    let size: CGFloat

    @State private var isOut: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(pet: PetCode, mood: Int, size: CGFloat) {
        self.pet = pet
        self.mood = mood
        self.size = size
        _isOut = State(initialValue: SnapshotMode.current != nil)
    }

    var body: some View {
        VStack(spacing: LKSpacing.s) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [LKColor.done.opacity(0.3), LKColor.done.opacity(0)],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.75
                    ))
                if isOut {
                    PetView(code: pet, mood: mood, size: size)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    PetView(code: PetCode(species: pet.species, stage: 0), mood: mood, size: size * 0.8)
                        .transition(.scale(scale: 1.2).combined(with: .opacity))
                }
            }
            .frame(width: size * 1.3, height: size * 1.3)
            Text("Your squad's egg hatched!")
                .font(LKFont.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Meet your \(PetNames.name(pet).lowercased())")
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textSecondary)
        }
        .sensoryFeedback(.success, trigger: isOut)
        .accessibilityElement(children: .combine)
        .task {
            guard !isOut else { return }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(reduceMotion ? nil : LKMotion.celebrate) {
                isOut = true
            }
        }
    }
}
