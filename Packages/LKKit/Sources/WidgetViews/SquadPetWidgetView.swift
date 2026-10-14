import Creature
import DesignSystem
import Model
import SwiftUI
import WidgetKit

/// The Squad pet widget: the pet, its mood, the streak and the squad's name (SPEC.md §1.5, "lives
/// in Home/Lock Screen widgets the rest of the time"). With no squad, your Lockling and your own
/// streak.
///
/// Small and medium on the Home Screen; circular and rectangular on the Lock Screen. The widget
/// extension passes in its family and whether it's drawn in full colour; the app's snapshots pass
/// each in turn. Out of full colour (the Lock Screen's vibrant mode, the Home Screen's tinted
/// one) the creatures become outlines with a light face, as in Always-On, and colour carries
/// nothing that the words don't.
public struct SquadPetWidgetView: View {
    private let content: PetWidgetContent
    private let family: WidgetFamily
    private let isFullColor: Bool

    public init(content: PetWidgetContent, family: WidgetFamily, isFullColor: Bool = true) {
        self.content = content
        self.family = family
        self.isFullColor = isFullColor
    }

    public var body: some View {
        Group {
            switch content {
            case .squad(let squad):
                squadBody(squad)
            case .solo(let avatar, let streak, let todayMinutes):
                soloBody(avatar: avatar, streak: streak, todayMinutes: todayMinutes)
            }
        }
        // Outlines out of full colour: one colour can't carry a gradient body and a dark face.
        .environment(\.isLuminanceReduced, !isFullColor)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder
    private func squadBody(_ squad: WidgetData.Squad) -> some View {
        switch family {
        case .systemMedium: SquadMedium(squad: squad, isFullColor: isFullColor)
        case .accessoryCircular: SquadCircular(squad: squad)
        case .accessoryRectangular: SquadRectangular(squad: squad)
        default: SquadSmall(squad: squad, isFullColor: isFullColor)
        }
    }

    @ViewBuilder
    private func soloBody(avatar: AvatarCode, streak: Int, todayMinutes: Int) -> some View {
        switch family {
        case .systemMedium: SoloMedium(avatar: avatar, streak: streak, todayMinutes: todayMinutes, isFullColor: isFullColor)
        case .accessoryCircular: SoloCircular(avatar: avatar, streak: streak)
        case .accessoryRectangular: SoloRectangular(avatar: avatar, streak: streak, todayMinutes: todayMinutes)
        default: SoloSmall(avatar: avatar, streak: streak, isFullColor: isFullColor)
        }
    }
}

extension PetWidgetContent {
    /// The colour behind the widget (`WidgetSurface`): the pet's mood, or your Lockling's colour.
    public var accent: Color {
        switch self {
        case .squad(let squad): LKColor.petMood(squad.mood)
        case .solo(let avatar, _, _): CreatureCatalogue.colour(avatar.colour)
        }
    }
}

// MARK: - Squad

/// About 138 points square inside the system's margins: the squad's name across the top, the pet
/// in the middle, the streak and the mood along the bottom.
private struct SquadSmall: View {
    let squad: WidgetData.Squad
    let isFullColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LKSpacing.xs) {
                Text(squad.name)
                    .font(LKFont.caption.weight(.semibold))
                    .foregroundStyle(LKColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if squad.lockedIn > 0 {
                    LiveDot(isFullColor: isFullColor)
                }
            }
            Spacer(minLength: 0)
            PetView(code: squad.petCode, mood: squad.mood, size: WidgetMetrics.smallCreature)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: LKSpacing.xs) {
                if squad.streak > 0 {
                    StreakLabel(days: squad.streak, isFullColor: isFullColor, compact: true)
                } else {
                    Text(WidgetWords.pet(squad.petCode))
                        .foregroundStyle(LKColor.textSecondary)
                }
                Spacer(minLength: LKSpacing.xs)
                MoodLabel(mood: squad.mood, isFullColor: isFullColor)
            }
            .font(LKFont.footnote.weight(.semibold))
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SquadWords.spoken(squad))
    }
}

/// The pet large on the left; on the right the name, its mood and stage, how far it has to grow,
/// and the streak and who's locked in now.
private struct SquadMedium: View {
    let squad: WidgetData.Squad
    let isFullColor: Bool

    var body: some View {
        HStack(spacing: LKSpacing.l) {
            PetView(code: squad.petCode, mood: squad.mood, size: WidgetMetrics.mediumCreature)
                .frame(width: WidgetMetrics.mediumCreature, height: WidgetMetrics.mediumCreature)
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                Text(squad.name)
                    .font(LKFont.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(spacing: LKSpacing.xs) {
                    MoodLabel(mood: squad.mood, isFullColor: isFullColor)
                    Text("·")
                    Text(WidgetWords.pet(squad.petCode))
                }
                .font(LKFont.subheadline.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
                if squad.petCode.growth == .egg {
                    Text("Hatches when you finish a session together")
                        .font(LKFont.caption.weight(.medium))
                        .foregroundStyle(LKColor.textSecondary)
                        .lineLimit(2)
                } else {
                    ProgressView(value: squad.clampedProgress)
                        .progressViewStyle(.linear)
                        .tint(isFullColor ? LKColor.petMood(squad.mood) : Color.primary)
                        .padding(.top, LKSpacing.xxs)
                }
                Spacer(minLength: 0)
                HStack(spacing: LKSpacing.m) {
                    StreakLabel(days: squad.streak, isFullColor: isFullColor, compact: false)
                    if squad.lockedIn > 0 {
                        Label {
                            Text(WidgetWords.lockedIn(squad.lockedIn))
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(isFullColor ? LKColor.focusing : Color.primary)
                        }
                    }
                }
                .font(LKFont.footnote.weight(.semibold))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SquadWords.spoken(squad))
    }
}

/// 76 points round on an iPhone 16 Pro's Lock Screen: the pet, and the streak under it.
private struct SquadCircular: View {
    let squad: WidgetData.Squad

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                PetView(
                    code: squad.petCode,
                    mood: squad.mood,
                    size: squad.streak > 0 ? WidgetMetrics.circularCreature : WidgetMetrics.circularCreatureAlone
                )
                if squad.streak > 0 {
                    CircularStreak(days: squad.streak)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SquadWords.spoken(squad))
    }
}

/// About 172 × 76: the pet, then the squad's name, the streak, and its mood and stage.
private struct SquadRectangular: View {
    let squad: WidgetData.Squad

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            PetView(code: squad.petCode, mood: squad.mood, size: WidgetMetrics.rectangularCreature)
            VStack(alignment: .leading, spacing: 0) {
                Text(squad.name)
                    .font(LKFont.headline)
                    .widgetAccentable()
                Label {
                    Text(WidgetWords.streak(squad.streak))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "flame.fill")
                }
                .font(LKFont.subheadline.weight(.medium))
                Text("\(WidgetWords.mood(squad.mood)) · \(WidgetWords.pet(squad.petCode))")
                    .font(LKFont.caption.weight(.medium))
                    .foregroundStyle(LKColor.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SquadWords.spoken(squad))
    }
}

// MARK: - Solo

/// No squad yet: your Lockling and your own streak.
private struct SoloSmall: View {
    let avatar: AvatarCode
    let streak: Int
    let isFullColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your streak")
                .font(LKFont.caption.weight(.semibold))
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            CreatureView(avatar: avatar, pose: .idle, size: WidgetMetrics.smallCreature)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            StreakLabel(days: streak, isFullColor: isFullColor, compact: false)
                .font(LKFont.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SoloWords.spoken(streak: streak, todayMinutes: nil))
    }
}

/// Your Lockling large, your streak in big type, today's minutes, and a nudge towards a squad.
private struct SoloMedium: View {
    let avatar: AvatarCode
    let streak: Int
    let todayMinutes: Int
    let isFullColor: Bool

    var body: some View {
        HStack(spacing: LKSpacing.l) {
            CreatureView(avatar: avatar, pose: .idle, size: WidgetMetrics.mediumCreature)
            VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                Text("Your streak")
                    .font(LKFont.subheadline.weight(.medium))
                    .foregroundStyle(LKColor.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: LKSpacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(isFullColor ? Color.orange : Color.primary)
                    Text(WidgetWords.streak(streak))
                        .monospacedDigit()
                        .widgetAccentable()
                }
                .font(.title2.weight(.bold))
                Text(WidgetWords.today(todayMinutes))
                    .font(LKFont.subheadline.weight(.medium))
                    .foregroundStyle(LKColor.textSecondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("Start a squad to hatch a pet")
                    .font(LKFont.caption.weight(.medium))
                    .foregroundStyle(LKColor.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SoloWords.spoken(streak: streak, todayMinutes: todayMinutes))
    }
}

private struct SoloCircular: View {
    let avatar: AvatarCode
    let streak: Int

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                CreatureView(
                    avatar: avatar,
                    pose: .idle,
                    size: streak > 0 ? WidgetMetrics.circularCreature : WidgetMetrics.circularCreatureAlone
                )
                if streak > 0 {
                    CircularStreak(days: streak)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SoloWords.spoken(streak: streak, todayMinutes: nil))
    }
}

private struct SoloRectangular: View {
    let avatar: AvatarCode
    let streak: Int
    let todayMinutes: Int

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            CreatureView(avatar: avatar, pose: .idle, size: WidgetMetrics.rectangularCreature)
            VStack(alignment: .leading, spacing: 0) {
                Text("Your streak")
                    .font(LKFont.headline)
                    .widgetAccentable()
                Label {
                    Text(WidgetWords.streak(streak))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "flame.fill")
                }
                .font(LKFont.subheadline.weight(.medium))
                Text(WidgetWords.today(todayMinutes))
                    .font(LKFont.caption.weight(.medium))
                    .foregroundStyle(LKColor.textSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SoloWords.spoken(streak: streak, todayMinutes: todayMinutes))
    }
}

// MARK: - Pieces

/// A flame and the streak. Compact drops the word "days": "4".
private struct StreakLabel: View {
    let days: Int
    let isFullColor: Bool
    let compact: Bool

    var body: some View {
        Label {
            Text(compact ? "\(days)" : WidgetWords.streak(days))
                .monospacedDigit()
        } icon: {
            Image(systemName: "flame.fill")
                .foregroundStyle(isFullColor ? Color.orange : Color.primary)
        }
        .labelStyle(TightLabelStyle())
    }
}

/// The flame and a number, under the pet in the circular widget.
private struct CircularStreak: View {
    let days: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "flame.fill")
            Text("\(days)")
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .widgetAccentable()
    }
}

/// The mood's dot and word, "● Happy".
private struct MoodLabel: View {
    let mood: Int
    let isFullColor: Bool

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            Circle()
                .fill(isFullColor ? LKColor.petMood(mood) : Color.primary)
                .frame(width: 7, height: 7)
            Text(WidgetWords.mood(mood))
        }
    }
}

/// A green dot: someone's locked in with the squad right now.
private struct LiveDot: View {
    let isFullColor: Bool

    var body: some View {
        Circle()
            .fill(isFullColor ? Color.green : Color.primary)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// A label whose icon sits close to its title, like the system's in a caption.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: LKSpacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

/// What VoiceOver says for a squad's widget.
private enum SquadWords {
    static func spoken(_ squad: WidgetData.Squad) -> Text {
        var parts = [squad.name, PetView.accessibilityLabel(code: squad.petCode, mood: squad.mood)]
        parts.append("Streak: \(WidgetWords.streak(squad.streak))")
        if squad.lockedIn > 0 {
            parts.append("\(WidgetWords.lockedIn(squad.lockedIn)) now")
        }
        return Text(verbatim: parts.joined(separator: ". "))
    }
}

/// What VoiceOver says for your own widget.
private enum SoloWords {
    static func spoken(streak: Int, todayMinutes: Int?) -> Text {
        var parts = ["Your streak: \(WidgetWords.streak(streak))"]
        if let todayMinutes {
            parts.append(WidgetWords.today(todayMinutes))
        }
        return Text(verbatim: parts.joined(separator: ". "))
    }
}

/// Sizes the widgets are drawn at, in points.
enum WidgetMetrics {
    /// The pet or Lockling in a small widget, under the name and over the streak.
    static let smallCreature: CGFloat = 76
    /// Beside the words in a medium widget.
    static let mediumCreature: CGFloat = 112
    /// Over the streak in the circular Lock Screen widget.
    static let circularCreature: CGFloat = 38
    /// Alone in the circular widget.
    static let circularCreatureAlone: CGFloat = 48
    /// Beside the words in the rectangular Lock Screen widget.
    static let rectangularCreature: CGFloat = 44
    /// The Lock in widget's Lockling.
    static let lockInCreature: CGFloat = 52
}
