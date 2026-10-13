import DesignSystem
import SwiftUI

// Pieces the Lock Screen and Dynamic Island views share.
//
// Live Activity rules (CLAUDE.md) that apply to everything in Views/:
// - No animation modifiers: the system ignores them. Only content transitions animate.
// - Countdowns are `Text(timerInterval:)` and progress is `ProgressView(timerInterval:)`, so they
//   tick on the device with no pushes.
// - No images from the network or asset catalogues: SF Symbols and shapes only.
// - With `isLuminanceReduced` (Always-On) nothing glows: monograms become outlines, bars dim.
//
// The look is design/SYSTEM.md's: system colours (the member states come from `LKMemberTone`),
// text in the hierarchical styles so it stays vibrant on the Lock Screen, and SF Pro through
// Dynamic Type text styles. Only the monograms' initials are SF Rounded, as in Contacts.

/// Type for the Live Activity: Dynamic Type text styles, so it sits beside Apple's own activities
/// and grows with the reader's text size, as far as each presentation has room for
/// (`ActivityTextSize`). The HIG asks Live Activities for text "a medium weight or higher", read
/// at a glance in secondary over the wallpaper or the island's black, so the smaller styles add
/// medium on top of their own. Headline is semibold already.
enum ActivityFont {
    /// The squad name, the solo headline and the expanded island's title: Headline.
    static let headline = LKFont.headline
    /// The solo status line under the headline: Subheadline medium.
    static let subheadline = LKFont.subheadline.weight(.medium)
    /// "1 of 6 locked in" beside or under the squad name, and "+2": Footnote medium.
    static let status = LKFont.footnote.weight(.medium)
    /// Names under monograms, and the pet row: Caption medium.
    static let caption = LKFont.caption.weight(.medium)
}

/// Which timer style each presentation uses (design/SYSTEM.md, "Live Activity"). Every one has
/// monospaced digits, so a ticking countdown doesn't shuffle sideways.
enum ActivityTimer {
    /// Your countdown on the Lock Screen: Title 2 semibold.
    static let lockScreen = LKTypeStyle.timerLockScreen
    /// Your countdown in the Dynamic Island, compact and expanded: Body semibold.
    static let island = LKTypeStyle.timerIsland
    /// Squadmates' countdowns under their monograms and in the island's chips: Subheadline
    /// semibold, a step under yours.
    static let squadmate = LKTypeStyle.timerSquadmate
    /// Your countdown beside the squad name in StandBy: 40 points, as large as fits beside it.
    static let standBySquad = LKTypeStyle.timerStandBySmall
    /// The Apple Watch Smart Stack: the Lock Screen's.
    static let smartStack = LKTypeStyle.timerLockScreen

    /// StandBy's solo hero: 72 points, unless the timer needs its hours digit. "1:29:59" at 72
    /// points is about 270 points wide, which beside the monogram is more than an iPhone has.
    static func standBySolo(for countdown: LiveActivityPresentation.Countdown) -> LKTypeStyle {
        countdown.needsHours ? .timerStandBySmall : .timerStandBy
    }
}

/// How far each presentation lets Dynamic Type grow.
///
/// Text follows the reader's text size as everywhere else, but every presentation is a fixed
/// space: the Lock Screen cuts content off past 160 points, StandBy scales that same view up
/// rather than laying it out again, the island's regions don't grow, and the Watch's Smart Stack
/// is about 160 × 70. Past these sizes text would be cut off rather than larger, so each view
/// holds its text to its range. LockScreenHeightTests measures every sample at the largest
/// accessibility size, which these ranges bring back to their top.
enum ActivityTextSize {
    /// One step past the default: the squad layout is about 152 points tall there.
    static let lockScreen = ...DynamicTypeSize.xLarge
    /// No larger than the default. StandBy already scales the whole view up about twice to fill
    /// the screen; the island and the Smart Stack are regions the system sizes.
    static let fixedRegion = ...DynamicTypeSize.large
}

/// Monogram sizes and margins per presentation.
enum ActivityMetrics {
    /// Compact leading and minimal: the island is 36.67 points tall, and a minimal presentation
    /// must fit 45 × 36.67 (SPEC.md §3).
    static let islandBadge: CGFloat = 22
    /// Beside the camera in the expanded island.
    static let expandedBadge: CGFloat = 40
    /// The expanded island's squad chips. Under `MemberBadge.symbolOnlyBelow`, so they show the
    /// state's symbol; the name is right beside it.
    static let expandedChipBadge: CGFloat = 22
    /// The Lock Screen's squad row: six fit across an iPhone SE.
    static let lockScreenRowBadge: CGFloat = 34
    /// The solo Lock Screen: the height of the headline and status line beside it.
    static let soloBadge: CGFloat = 44
    static let soloStandByBadge: CGFloat = 64
    /// The Apple Watch Smart Stack.
    static let smartStackBadge: CGFloat = 24
    /// A member column never grows wider than this, so a squad of two doesn't sprawl.
    static let columnMaxWidth: CGFloat = 72
    /// The Lock Screen's side margin: Apple's standard layout margin for Live Activities there
    /// (Human Interface Guidelines, Live Activities), so our text lines up with the notifications
    /// above and below. The one exception to the 4-point grid; the value is Apple's, not ours.
    static let lockScreenMargin: CGFloat = 14

    /// Every monogram size the presentations draw, for the tests.
    static let badgeSizes: [CGFloat] = [
        islandBadge, expandedBadge, expandedChipBadge, lockScreenRowBadge, soloBadge, soloStandByBadge, smartStackBadge,
    ]
}

extension View {
    /// The Dynamic Island's appearance: dark, whatever the phone's, with text no larger than the
    /// regions hold.
    ///
    /// The island is black in both appearances; Apple's guidance is white text on it. In the dark
    /// appearance `.primary` is white and the state colours take their dark variants, which are
    /// made for black. The system draws the island that way already; saying so here keeps the
    /// Lab's island honest whatever the app's own appearance.
    func islandAppearance() -> some View {
        environment(\.colorScheme, .dark)
            .dynamicTypeSize(ActivityTextSize.fixedRegion)
    }
}

extension LiveActivityPresentation.Countdown {
    /// The countdown as text. Running timers tick on the device; paused ones show `end - pausedAt`
    /// and stay there.
    var timerText: Text {
        switch self {
        case .running(let range):
            return Text(timerInterval: range, countsDown: true, showsHours: true)
        case .paused(let range, let pausedAt):
            return Text(timerInterval: range, pauseTime: pausedAt, countsDown: true, showsHours: true)
        case .text(let words):
            return Text(words)
        }
    }
}

/// A member's countdown, or their state as a quiet word.
struct CountdownText: View {
    enum Sizing {
        /// A fixed frame sized for the longest reading (`Countdown.reservedWidth(fontSize:)`).
        case reserved
        /// All the width offered, for columns that already have a width.
        case fill
    }

    /// What a timer is drawn in.
    enum Ink: Equatable {
        /// The state's colour: your own time, the one the presentation is about. Only in the dark
        /// appearance, where the state colours are made for black: the island, StandBy,
        /// Always-On, the Smart Stack and the dark Lock Screen. On the light Lock Screen it
        /// resolves to primary (`resolve(_:for:in:)`).
        case tone
        /// The primary text style: squadmates' times, whose monograms already carry the colour.
        case primary
        /// The secondary text style. Words ("Done", "Left") always take it, whatever was asked:
        /// a finished member steps back.
        case secondary
    }

    let countdown: LiveActivityPresentation.Countdown
    let tone: LKMemberTone
    let style: LKTypeStyle
    let alignment: HorizontalAlignment
    let sizing: Sizing
    let ink: Ink
    /// The style's size at the reader's text size, for the reserved frame. Text that scales
    /// would otherwise outgrow a frame worked out at the default size and be squeezed by
    /// `minimumScaleFactor`.
    @ScaledMetric private var scaledFontSize: CGFloat
    /// The appearance the presentation is drawn in, which decides whether `.tone` can be read.
    @Environment(\.colorScheme) private var colorScheme

    init(
        countdown: LiveActivityPresentation.Countdown,
        tone: LKMemberTone,
        style: LKTypeStyle,
        alignment: HorizontalAlignment = .trailing,
        sizing: Sizing = .reserved,
        ink: Ink = .tone
    ) {
        self.countdown = countdown
        self.tone = tone
        self.style = style
        self.alignment = alignment
        self.sizing = sizing
        self.ink = ink
        // A fixed style never reads it (`fontSize`); `.body` is only somewhere to point it.
        _scaledFontSize = ScaledMetric(wrappedValue: style.pointSize, relativeTo: style.textStyle ?? .body)
    }

    var body: some View {
        countdown.timerText
            .font(style.font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            // Insurance for the reserved widths, which are estimates.
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(textAlignment)
            .frame(width: sizing == .reserved ? countdown.reservedWidth(fontSize: fontSize) : nil,
                   alignment: Alignment(horizontal: alignment, vertical: .center))
            .frame(maxWidth: sizing == .fill ? CGFloat.infinity : nil,
                   alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    /// The ink a countdown is drawn in. A word is always secondary. The state colours are made for
    /// black: on the light Lock Screen's default background teal, orange and green are under 3:1 as
    /// text, so your own time takes the primary style there. The monogram, its status badge and the
    /// bar still carry the colour.
    static func resolve(_ ink: Ink, for countdown: LiveActivityPresentation.Countdown, in scheme: ColorScheme) -> Ink {
        if countdown.staticText != nil { return .secondary }
        if ink == .tone && scheme == .light { return .primary }
        return ink
    }

    /// The ink actually used, in the appearance this view is drawn in.
    var resolvedInk: Ink {
        Self.resolve(ink, for: countdown, in: colorScheme)
    }

    private var fontSize: CGFloat {
        style.scalesWithDynamicType ? scaledFontSize : style.pointSize
    }

    // The hierarchical styles and a `Color` are different types, so they meet as `AnyShapeStyle`.
    private var foreground: AnyShapeStyle {
        switch resolvedInk {
        case .tone: return AnyShapeStyle(tone.color)
        case .primary: return AnyShapeStyle(LKColor.textPrimary)
        case .secondary: return AnyShapeStyle(LKColor.textSecondary)
        }
    }

    private var textAlignment: TextAlignment {
        if alignment == .leading { return .leading }
        if alignment == .trailing { return .trailing }
        return .center
    }
}

/// A session filling up as it runs, in the system's own linear bar. Decorative: the countdown
/// beside it says the same thing.
struct SessionProgressBar: View {
    let progress: LiveActivityPresentation.SessionProgress
    let tint: Color
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        bar
            .progressViewStyle(.linear)
            .tint(isLuminanceReduced ? tint.opacity(0.5) : tint)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bar: some View {
        switch progress {
        case .live(let range):
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        case .fixed(let value):
            ProgressView(value: value)
        case .hidden:
            EmptyView()
        }
    }
}

/// A member as a column, like a share sheet's people: monogram, name, countdown. One VoiceOver
/// element that names them, says their state and reads a running timer as its value.
///
/// About 68 points tall at the default text size: monogram 34 + 2 + name 14 + countdown 18.
struct MemberColumn: View {
    let member: LiveActivityPresentation.Member
    let badgeSize: CGFloat

    var body: some View {
        VStack(spacing: LKSpacing.xxs) {
            MemberBadge(member, size: badgeSize)
            VStack(spacing: 0) {
                Text(member.name)
                    .font(ActivityFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
                    .lineLimit(1)
                CountdownText(
                    countdown: member.countdown,
                    tone: member.tone,
                    style: ActivityTimer.squadmate,
                    alignment: .center,
                    sizing: .fill,
                    ink: .primary
                )
            }
        }
        .frame(maxWidth: ActivityMetrics.columnMaxWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.accessibilityLabel)
        .accessibilityCountdownValue(member.countdown)
    }
}

/// A member as a chip for the expanded island: a small monogram beside their name and countdown.
/// About 32 points tall, half a column's height, which leaves room under the row for M1's
/// buttons.
struct MemberChip: View {
    let member: LiveActivityPresentation.Member

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            MemberBadge(member, size: ActivityMetrics.expandedChipBadge)
            VStack(alignment: .leading, spacing: 0) {
                Text(member.name)
                    .font(ActivityFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
                    .lineLimit(1)
                CountdownText(
                    countdown: member.countdown,
                    tone: member.tone,
                    style: ActivityTimer.squadmate,
                    alignment: .leading,
                    sizing: .fill,
                    ink: .primary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.accessibilityLabel)
        .accessibilityCountdownValue(member.countdown)
    }
}

/// Squadmates who didn't fit in the expanded row, as "+2".
struct OverflowLabel: View {
    let count: Int

    var body: some View {
        Text(verbatim: "+\(count)")
            .font(ActivityFont.status.monospacedDigit())
            .foregroundStyle(LKColor.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .accessibilityLabel(label)
    }

    private var label: String {
        count == 1 ? "1 more squadmate" : "\(count) more squadmates"
    }
}

/// The squad pet: a paw in its mood's colour, its species and stage, and progress to the next
/// stage. Stands in for the drawn pet (`Creature`, M1; moods and stages, M5).
struct PetRow: View {
    let pet: LiveActivityPresentation.Pet
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(LKColor.petMood(pet.mood))
            Text(pet.title)
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            ProgressView(value: pet.progress)
                .progressViewStyle(.linear)
                .tint(LKColor.petMood(pet.mood).opacity(isLuminanceReduced ? 0.5 : 1))
        }
        .font(ActivityFont.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pet.accessibilityLabel)
    }
}

/// "1 of 6 locked in", behind a lock in the focusing colour. A `Label`, as the system would
/// write it: the symbol is decorative and VoiceOver reads the words.
struct SquadStatus: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(LKColor.textSecondary)
        } icon: {
            Image(systemName: LKMemberTone.focusing.symbolName)
                .foregroundStyle(LKMemberTone.focusing.color)
        }
        .labelStyle(.titleAndIcon)
        .font(ActivityFont.status)
        .lineLimit(1)
    }
}

extension View {
    /// Gives VoiceOver a running countdown's live time as the value, under a label that already
    /// names the member and state (a frozen time is in the label).
    @ViewBuilder
    func accessibilityCountdownValue(_ countdown: LiveActivityPresentation.Countdown) -> some View {
        switch countdown {
        case .running(let range):
            accessibilityValue(Text(timerInterval: range, countsDown: true))
        case .paused, .text:
            self
        }
    }
}
