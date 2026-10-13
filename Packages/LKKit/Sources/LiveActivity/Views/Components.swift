import DesignSystem
import SwiftUI

// Pieces the Lock Screen and Dynamic Island views share.
//
// Live Activity rules (CLAUDE.md) that apply to everything in Views/:
// - No animation modifiers: the system ignores them. Only content transitions animate.
// - Countdowns are `Text(timerInterval:)` and progress is `ProgressView(timerInterval:)`, so they
//   tick on the device with no pushes.
// - No images from the network or asset catalogues: SF Symbols and shapes only.
// - With `isLuminanceReduced` (Always-On) nothing glows: badges become outlines, bars dim.

/// Type for the Live Activity. Fixed sizes rather than Dynamic Type styles: the Lock Screen
/// presentation is cut off past 160 points and the island's regions don't grow, so text that
/// scaled up would be lost. The timers use the fixed `LKTypeStyle` timer styles.
enum ActivityFont {
    /// The squad name, and the solo headline.
    static let headline = Font.system(size: 15, weight: .bold, design: .rounded)
    /// The solo headline beside a large badge.
    static let soloHeadline = Font.system(size: 17, weight: .bold, design: .rounded)
    /// Names under badges.
    static let name = Font.system(size: 12, weight: .semibold, design: .rounded)
    /// Status lines and the pet row.
    static let caption = Font.system(size: 11, weight: .medium, design: .rounded)
}

/// Badge sizes per presentation.
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
    /// The solo Lock Screen.
    static let soloBadge: CGFloat = 52
    static let soloStandByBadge: CGFloat = 64
    /// The Apple Watch Smart Stack.
    static let smartStackBadge: CGFloat = 24
    /// A member column never grows wider than this, so a squad of two doesn't sprawl.
    static let columnMaxWidth: CGFloat = 72
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

/// A member's countdown, in their state's colour, or their state as a quiet word.
struct CountdownText: View {
    enum Sizing {
        /// A fixed frame sized for the longest reading (`Countdown.reservedWidth(fontSize:)`).
        case reserved
        /// All the width offered, for columns that already have a width.
        case fill
    }

    let countdown: LiveActivityPresentation.Countdown
    let tone: LKMemberTone
    let style: LKTypeStyle
    var alignment: HorizontalAlignment = .trailing
    var sizing: Sizing = .reserved

    var body: some View {
        countdown.timerText
            .font(style.font)
            .foregroundStyle(countdown.staticText == nil ? tone.color : LKColor.textSecondary)
            .lineLimit(1)
            // Insurance for the reserved widths, which are estimates.
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(textAlignment)
            .frame(width: sizing == .reserved ? countdown.reservedWidth(fontSize: style.pointSize) : nil,
                   alignment: Alignment(horizontal: alignment, vertical: .center))
            .frame(maxWidth: sizing == .fill ? CGFloat.infinity : nil,
                   alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var textAlignment: TextAlignment {
        if alignment == .leading { return .leading }
        if alignment == .trailing { return .trailing }
        return .center
    }
}

/// A session filling up as it runs. Decorative: the countdown beside it says the same thing.
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

/// A member as a column: badge, name, countdown. One VoiceOver element that names them, says
/// their state and reads a running timer as its value.
struct MemberColumn: View {
    let member: LiveActivityPresentation.Member
    let badgeSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            MemberBadge(member, size: badgeSize)
            Text(member.name)
                .font(ActivityFont.name)
                .foregroundStyle(LKColor.textPrimary)
                .lineLimit(1)
            CountdownText(
                countdown: member.countdown,
                tone: member.tone,
                style: .timerCompact,
                alignment: .center,
                sizing: .fill
            )
        }
        .frame(maxWidth: ActivityMetrics.columnMaxWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.accessibilityLabel)
        .accessibilityCountdownValue(member.countdown)
    }
}

/// A member as a chip for the expanded island: a small badge beside their name and countdown.
/// About 33 points tall, half a column's height, which leaves room under the row for M1's buttons.
struct MemberChip: View {
    let member: LiveActivityPresentation.Member

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            MemberBadge(member, size: ActivityMetrics.expandedChipBadge)
            VStack(alignment: .leading, spacing: 0) {
                Text(member.name)
                    .font(ActivityFont.name)
                    .foregroundStyle(LKColor.textPrimary)
                    .lineLimit(1)
                CountdownText(
                    countdown: member.countdown,
                    tone: member.tone,
                    style: .timerCompact,
                    alignment: .leading,
                    sizing: .fill
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
            .font(ActivityFont.name)
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

/// "1 of 6 locked in", behind a lock in the focusing colour.
struct SquadStatus: View {
    let text: String

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            Image(systemName: LKMemberTone.focusing.symbolName)
                .foregroundStyle(LKColor.focusing)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
        }
        .font(ActivityFont.caption)
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
