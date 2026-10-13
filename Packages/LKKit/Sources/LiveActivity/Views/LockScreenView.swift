import DesignSystem
import Model
import SwiftUI
import WidgetKit

/// The Lock Screen presentation. The system also uses it for the banner on iPhones without a
/// Dynamic Island, for StandBy (scaled up to fill the screen), and, at the small activity family,
/// for the Apple Watch Smart Stack.
///
/// It draws no background: the widget extension sets
/// `activityBackgroundTint(LKColor.liveActivityBackground)`, and the Live Activity Lab should draw
/// the same colour behind it. Text and badges are in the night appearance whatever the system's,
/// because they're tuned for that background.
///
/// Squad: the squad name and how many are locked in, a row of up to six members with their own
/// countdowns, and the pet. Solo: your badge, what you're doing, your countdown and a bar that
/// fills as the session runs. Both stay under 160 points tall, StandBy included, where the system
/// starts cutting content off (SPEC.md §3; LockScreenHeightTests checks every sample).
public struct LockScreenView: View {
    /// Which layout to draw.
    public enum Layout: Hashable, Sendable {
        /// Whatever the system is showing: StandBy when `isActivityFullscreen`, the Smart Stack
        /// at the `.small` activity family, otherwise the Lock Screen.
        case automatic
        case lockScreen
        /// The "desk mode" shot (SPEC.md §1.7): your time as the hero. The system scales the
        /// whole view up to fill the screen.
        case standBy
        /// Apple Watch (and CarPlay) at the small activity family: you, your time and the count.
        case smartStack
    }

    private let presentation: LiveActivityPresentation
    private let layout: Layout
    @Environment(\.isActivityFullscreen) private var isActivityFullscreen
    @Environment(\.activityFamily) private var activityFamily

    /// - Parameter layout: `.automatic` in the widget extension. The Lab passes the others:
    ///   `isActivityFullscreen` is read-only, so an app can't put a view in StandBy by setting it.
    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState, layout: Layout = .automatic) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
        self.layout = layout
    }

    public var body: some View {
        content
            .lkNightAppearance()
    }

    @ViewBuilder
    private var content: some View {
        let resolved = resolvedLayout
        switch resolved {
        case .smartStack:
            SmartStackLayout(presentation: presentation)
        case .automatic, .lockScreen, .standBy:
            if presentation.isSolo {
                SoloLayout(presentation: presentation, isStandBy: resolved == .standBy)
            } else {
                SquadLayout(presentation: presentation, isStandBy: resolved == .standBy)
            }
        }
    }

    private var resolvedLayout: Layout {
        guard layout == .automatic else { return layout }
        switch activityFamily {
        case .small:
            return .smartStack
        default:
            return isActivityFullscreen ? .standBy : .lockScreen
        }
    }
}

// MARK: - Squad

/// About 145 points tall with a pet: 12 + header 18 + 10 + row 70 + 10 + pet 13 + 12.
///
/// StandBy puts your countdown in the header, about 48 points tall at `.timerLarge`, and moves
/// the pet up beside it, under the squad name and status (18 + 2 + 13 + 2 + 13). That keeps it
/// about 152 points: 12 + header 48 + 10 + row 70 + 12. The system scales it up from there, but
/// truncates past 160 points just as on the Lock Screen (LockScreenHeightTests measures both).
private struct SquadLayout: View {
    let presentation: LiveActivityPresentation
    let isStandBy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: LKSpacing.xs) {
                ForEach(presentation.lockScreenMembers) { member in
                    MemberColumn(member: member, badgeSize: ActivityMetrics.lockScreenRowBadge)
                }
            }
            .frame(maxWidth: .infinity)
            if !isStandBy, let pet = presentation.pet {
                PetRow(pet: pet)
            }
        }
        .padding(.horizontal, LKSpacing.l)
        .padding(.vertical, LKSpacing.m)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: LKSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.headline)
                        .font(ActivityFont.headline)
                        .foregroundStyle(LKColor.textPrimary)
                        .lineLimit(1)
                    if isStandBy {
                        SquadStatus(text: presentation.statusLine)
                    }
                }
                .accessibilityElement(children: .combine)
                if isStandBy, let pet = presentation.pet {
                    PetRow(pet: pet)
                }
            }
            // In StandBy the width the countdown leaves goes to this column, not the spacer, so
            // the pet's bar and a long squad name aren't squeezed.
            .layoutPriority(isStandBy ? 1 : 0)
            Spacer(minLength: LKSpacing.s)
            if isStandBy, let me = presentation.primary {
                CountdownText(countdown: me.countdown, tone: me.tone, style: .timerLarge)
                    // Its full width first: the pet's bar beside it would take any it gave up,
                    // and a word ("Done") has no reserved frame to hold it.
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel(me.accessibilityLabel)
                    .accessibilityCountdownValue(me.countdown)
            } else if !isStandBy {
                // StandBy already shows it under the squad name.
                SquadStatus(text: presentation.statusLine)
            }
        }
    }
}

// MARK: - Solo

/// About 90 points tall: 12 + badge 52 + 12 + bar 4 + 12. StandBy swaps in the hero timer.
private struct SoloLayout: View {
    let presentation: LiveActivityPresentation
    let isStandBy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            HStack(spacing: LKSpacing.m) {
                if let me = presentation.primary {
                    MemberBadge(me, size: isStandBy ? ActivityMetrics.soloStandByBadge : ActivityMetrics.soloBadge)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.headline)
                        .font(ActivityFont.soloHeadline)
                        .foregroundStyle(LKColor.textPrimary)
                        .lineLimit(1)
                    Text(presentation.statusLine)
                        .font(ActivityFont.caption)
                        .foregroundStyle(LKColor.textSecondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                .accessibilityElement(children: .combine)
                Spacer(minLength: LKSpacing.s)
                if let me = presentation.primary {
                    CountdownText(countdown: me.countdown, tone: me.tone, style: timerStyle(for: me.countdown))
                        .accessibilityLabel(me.accessibilityLabel)
                        .accessibilityCountdownValue(me.countdown)
                }
            }
            SessionProgressBar(progress: presentation.sessionProgress, tint: presentation.primary?.tone.color ?? LKColor.accent)
        }
        .padding(.horizontal, LKSpacing.l)
        .padding(.vertical, LKSpacing.m)
    }

    /// The hero size in StandBy, unless the timer needs its hours digit: "1:29:59" at 72 points
    /// would leave no room for the headline.
    private func timerStyle(for countdown: LiveActivityPresentation.Countdown) -> LKTypeStyle {
        isStandBy && !countdown.needsHours ? .timerHero : .timerLarge
    }
}

// MARK: - Smart Stack

/// The small activity family: about 160 × 70 points on Apple Watch, with the system's margins
/// around it. You, your time, and how many are locked in.
private struct SmartStackLayout: View {
    let presentation: LiveActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xxs) {
            HStack(spacing: LKSpacing.s) {
                if let me = presentation.primary {
                    MemberBadge(me, size: ActivityMetrics.smartStackBadge)
                }
                Text(presentation.headline)
                    .font(ActivityFont.name)
                    .foregroundStyle(LKColor.textPrimary)
                    .lineLimit(1)
            }
            if let me = presentation.primary {
                CountdownText(countdown: me.countdown, tone: me.tone, style: .timer, alignment: .leading, sizing: .fill)
                    .accessibilityLabel(me.accessibilityLabel)
                    .accessibilityCountdownValue(me.countdown)
            }
            if !presentation.isSolo {
                SquadStatus(text: presentation.statusLine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
