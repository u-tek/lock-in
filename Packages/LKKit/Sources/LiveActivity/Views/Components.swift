import Creature
import DesignSystem
import Model
import SwiftUI

// Pieces the Lock Screen and Dynamic Island views share.
//
// Live Activity rules (CLAUDE.md) that apply to everything in Views/:
// - No animation modifiers: the system ignores them. Only content transitions animate.
// - Countdowns are `Text(timerInterval:)` and progress is `ProgressView(timerInterval:)`, so they
//   tick on the device with no pushes.
// - No images from the network or asset catalogues: SF Symbols and shapes only. Members are
//   Locklings (`CreatureView`), drawn in shapes from their avatar codes; the squad pet is a
//   `PetView`, drawn from its pet code.
// - With `isLuminanceReduced` (Always-On) nothing glows: Locklings and the pet become outlines,
//   bars dim.
// - No padding of our own inside the island: the system's region margins place everything.
//
// The look is design/SYSTEM.md's: system colours (the member states come from `LKMemberTone`),
// text in the hierarchical styles so it stays vibrant on the Lock Screen, and SF Pro through
// Dynamic Type text styles.

/// Type for the Live Activity: Dynamic Type text styles, so it sits beside Apple's own activities
/// and grows with the reader's text size, as far as each presentation has room for
/// (`ActivityTextSize`). The HIG asks Live Activities for text "a medium weight or higher", read
/// at a glance in secondary over the wallpaper or the island's black, so the smaller styles add
/// medium on top of their own. Headline is semibold already.
enum ActivityFont {
    /// The squad name, the solo headline and the expanded island's title: Headline.
    static let headline = LKFont.headline
    /// "1 of 6 locked in" beside or under the squad name: Footnote medium.
    static let status = LKFont.footnote.weight(.medium)
    /// Names under Locklings, and the pet row: Caption medium.
    static let caption = LKFont.caption.weight(.medium)
}

/// Which timer style each presentation uses (design/SYSTEM.md, "Live Activity"). Every one has
/// monospaced digits, so a ticking countdown doesn't shuffle sideways.
enum ActivityTimer {
    /// Your countdown on the Lock Screen: Title 2 semibold.
    static let lockScreen = LKTypeStyle.timerLockScreen
    /// Your countdown in the compact island: Body semibold, narrow enough to sit snug against
    /// the camera.
    static let island = LKTypeStyle.timerIsland
    /// Your countdown beside the camera in the expanded island: Title 2 semibold, the Lock
    /// Screen's size, so the time is the biggest thing there.
    static let expanded = LKTypeStyle.timerLockScreen
    /// Squadmates' countdowns under their Locklings: Subheadline semibold, a step under yours.
    static let squadmate = LKTypeStyle.timerSquadmate
    /// Your countdown beside the squad name in StandBy: 40 points, as large as fits beside it.
    static let standBySquad = LKTypeStyle.timerStandBySmall
    /// The Apple Watch Smart Stack: the Lock Screen's.
    static let smartStack = LKTypeStyle.timerLockScreen

    /// StandBy's solo hero: 72 points, unless the timer needs its hours digit. "1:29:59" at 72
    /// points is about 270 points wide, which beside the Lockling is more than an iPhone has.
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

/// Lockling sizes and margins per presentation. A Lockling fills its square and stays inside it
/// in every pose, so these are the sizes laid out, with no padding round them. From 28 points up
/// it draws its hat and what it's holding; under that, just the lock and its face.
enum ActivityMetrics {
    /// Compact leading and minimal: the island is 36.67 points tall, the HIG's limited-width
    /// presentations are a 28-point circle, and a minimal presentation must fit 45 × 36.67
    /// (SPEC.md §3). 24 sits inside all three with room to breathe.
    static let islandCreature: CGFloat = 24
    /// Beside the camera in the expanded island.
    static let expandedCreature: CGFloat = 44
    /// The expanded island's squad row: just big enough to show hats and props.
    static let expandedRowCreature: CGFloat = 30
    /// The Lock Screen's squad row: six fit across an iPhone SE.
    static let lockScreenRowCreature: CGFloat = 34
    /// The solo Lock Screen.
    static let soloCreature: CGFloat = 52
    /// StandBy's solo layout, beside the hero timer and about as tall.
    static let soloStandByCreature: CGFloat = 84
    /// The Apple Watch Smart Stack.
    static let smartStackCreature: CGFloat = 24
    /// A member column never grows wider than this, so a squad of two doesn't sprawl.
    static let columnMaxWidth: CGFloat = 72
    /// The Lock Screen's side margin: Apple's standard layout margin for Live Activities there
    /// (Human Interface Guidelines, Live Activities), so our text lines up with the notifications
    /// above and below. The one exception to the 4-point grid; the value is Apple's, not ours.
    static let lockScreenMargin: CGFloat = 14

    /// Every Lockling size the presentations draw, for the tests.
    static let creatureSizes: [CGFloat] = [
        islandCreature, expandedCreature, expandedRowCreature, lockScreenRowCreature, soloCreature,
        soloStandByCreature, smartStackCreature,
    ]

    /// The squad pet in its row on the Lock Screen and in StandBy: a little larger than the
    /// caption line beside it, so a baby is still a face (`PetView` keeps its outline and face
    /// below 28 points and drops the rest).
    static let petRowCreature: CGFloat = 18
    /// How far the pet reaches into the space above and below its row. The row is laid out as tall
    /// as its text (Caption, 14.3 points at the default size) rather than the pet, so the layouts'
    /// heights, and LockScreenHeightTests' 160-point limit, are what they were with the paw.
    static let petRowOverhang: CGFloat = 2
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
        /// The primary text style: squadmates' times, whose Locklings already show their state.
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
    /// text, so your own time takes the primary style there. The Lockling's pose and the bar still
    /// carry the state.
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

/// A member as a column, like a share sheet's people: their Lockling, name and countdown. One
/// VoiceOver element that names them, says their state and reads a running timer as its value.
///
/// About 68 points tall at the default text size on the Lock Screen: Lockling 34 + 2 + name 14.3
/// + countdown 18; 64 in the expanded island's 30-point row.
struct MemberColumn: View {
    let member: LiveActivityPresentation.Member
    let creatureSize: CGFloat

    var body: some View {
        VStack(spacing: LKSpacing.xxs) {
            MemberBadge(member, size: creatureSize)
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

/// A solo session's buttons: Pause or Resume, and End, as bordered capsules. Pause and Resume
/// take the tint; End is neutral, so the everyday action is the one that stands out.
///
/// Each is a `Button(intent:)`: the system runs the intent in the app's process, the app's
/// session engine does the work and updates the activity (`SessionIntentBridge`). Nothing is
/// drawn when there's nothing to control. The caller picks the control size.
struct SessionButtons: View {
    let controls: LiveActivityPresentation.SessionControls
    /// Both buttons share the width: the expanded island. On the Lock Screen they stay snug.
    let fillsWidth: Bool

    var body: some View {
        if controls != .hidden {
            HStack(spacing: LKSpacing.s) {
                primaryButton
                    .tint(LKColor.tint)
                Button(intent: EndSessionIntent()) {
                    label("End", systemImage: "xmark")
                }
                // Neutral: the label in the primary style on a quiet grey capsule.
                .tint(Color.primary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch controls {
        case .pauseAndEnd:
            Button(intent: PauseSessionIntent()) {
                label("Pause", systemImage: "pause.fill")
            }
        case .resumeAndEnd:
            Button(intent: ResumeSessionIntent()) {
                label("Resume", systemImage: "play.fill")
            }
        case .hidden:
            EmptyView()
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
    }
}

/// The squad pet: the pet itself, in its mood, then its species and stage, and its progress to
/// the next stage in its mood's colour. One VoiceOver element that names the pet, its stage and
/// mood, and how far it has to go.
///
/// The pet is drawn `ActivityMetrics.petRowOverhang` taller than the row above and below, into the
/// spacing round it, so the row is as tall as its caption: the Lock Screen and StandBy layouts were
/// measured with a paw there and stay under 160 points (LockScreenHeightTests).
struct PetRow: View {
    let pet: LiveActivityPresentation.Pet
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            PetView(code: pet.code, mood: pet.mood, size: ActivityMetrics.petRowCreature)
                .padding(.vertical, -ActivityMetrics.petRowOverhang)
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
///
/// While a cheer for you is in the content-state, the same line says who sent it instead ("Noor
/// cheered you on", behind the cheer's symbol), so the layout around it doesn't move or grow.
struct SquadStatus: View {
    let text: String
    var cheer: LiveActivityPresentation.Cheer? = nil

    var body: some View {
        Group {
            if let cheer {
                CheerLine(cheer: cheer, ink: LKColor.textSecondary)
            } else {
                Label {
                    Text(text)
                        .foregroundStyle(LKColor.textSecondary)
                } icon: {
                    Image(systemName: LKMemberTone.focusing.symbolName)
                        .foregroundStyle(LKMemberTone.focusing.color)
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .font(ActivityFont.status)
        .lineLimit(1)
    }
}

/// A cheer's symbol in its own colour. In Always-On nothing glows, so it's the symbol's outline
/// in the secondary style there, as the Locklings become outlines.
///
/// When a new cheer replaces one of another kind the symbol swaps with the system's replace
/// effect: a content transition, which Live Activities do animate (an animation modifier they'd
/// ignore). The caller gives VoiceOver the cheer in words: the symbol's own name says nothing
/// about who sent it.
struct CheerSymbol: View {
    let kind: CheerKind
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Image(systemName: isLuminanceReduced ? kind.outlineSymbolName : kind.symbolName)
            .foregroundStyle(ink)
            .contentTransition(.symbolEffect(.replace))
    }

    // The hierarchical style and a `Color` are different types, so they meet as `AnyShapeStyle`.
    private var ink: AnyShapeStyle {
        isLuminanceReduced ? AnyShapeStyle(LKColor.textSecondary) : AnyShapeStyle(LKColor.cheer(kind.rawValue))
    }
}

/// "Noor cheered you on" behind the cheer's symbol, on one line: the expanded island's line under
/// the camera, and the Lock Screen's and StandBy's status line, for as long as the room holds the
/// cheer. The caller sets the font. One VoiceOver element: "Noor cheered you on, heart".
struct CheerLine<Ink: ShapeStyle>: View {
    let cheer: LiveActivityPresentation.Cheer
    /// The words' style; the symbol keeps its own colour.
    let ink: Ink

    var body: some View {
        Label {
            Text(cheer.text)
                .foregroundStyle(ink)
        } icon: {
            CheerSymbol(kind: cheer.kind)
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cheer.accessibilityLabel)
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
