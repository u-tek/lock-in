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
/// next stage.
struct SquadPetCard: View {
    let pet: SquadPet

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

/// The squad's streak: a flame, the days, and how many have counted today.
struct SquadStreakRow: View {
    let streak: SquadStreak

    var body: some View {
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
        .padding(.vertical, LKSpacing.xxs)
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

/// One member's week: their place, their Lockling, their name and their minutes. Minutes show as
/// a placeholder until the leaderboard has loaded.
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
            Spacer(minLength: LKSpacing.s)
            Text("\(entry?.minutes ?? 0, format: .number) min")
                .font(LKFont.body)
                .foregroundStyle(LKColor.textSecondary)
                .monospacedDigit()
                .redacted(reason: entry == nil ? .placeholder : [])
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
