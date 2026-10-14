import DesignSystem
import Model
import SwiftUI
import WidgetKit

/// The Lock Screen presentation. The system also uses it for the banner on iPhones without a
/// Dynamic Island, for StandBy (scaled up to fill the screen), and, at the small activity family,
/// for the Apple Watch Smart Stack.
///
/// It draws no background and the widget extension sets none (no `activityBackgroundTint`), so it
/// sits on the system's default Live Activity background like Apple's own activities, and follows
/// the system's appearance (design/SYSTEM.md). Text uses the hierarchical styles, which stay
/// vibrant there; colour comes from the Locklings, the bar, and your own countdown only in the
/// dark appearance, since the state colours are made for black and too faint as text on the light
/// background (`CountdownText.resolve(_:for:in:)`). Two places are always dark: StandBy, which is
/// full-bleed black, and Always-On, which the system draws "as if in Dark Mode". The view says so
/// itself, so the Live Activity Lab's stand-ins match.
///
/// Squad: the squad name and how many are locked in, a row of up to six Locklings with names and
/// their own countdowns, and the pet. While a cheer for you is in the content-state, the count's
/// line says who sent it instead ("Noor cheered you on"), so nothing moves. Solo: your Lockling,
/// what you're doing, your countdown, a bar that fills as the session runs, and Pause or Resume
/// and End. StandBy swaps in a big Lockling and a huge countdown, and leaves the buttons for the
/// phone in your hand. Every layout stays under 160 points tall, StandBy included, where the
/// system starts cutting content off (SPEC.md §3).
/// Text grows with Dynamic Type only as far as that allows (`ActivityTextSize`);
/// LockScreenHeightTests checks every sample at the default and the largest text sizes.
///
/// The height estimates in the layouts below use SF Pro's line height, about 1.19 times the point
/// size, rounded to the pixel: Headline 20.3, Subheadline 18, Footnote 15.7, Caption 14.3,
/// Title 2 26.3, and one step up (xLarge) Headline 22.7, Subheadline 20.3, Footnote 17.9,
/// Caption 16.7, Title 2 28.6. Locklings are fixed sizes.
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
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameter layout: `.automatic` in the widget extension. The Lab passes the others:
    ///   `isActivityFullscreen` is read-only, so an app can't put a view in StandBy by setting it.
    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState, layout: Layout = .automatic) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
        self.layout = layout
    }

    public var body: some View {
        let resolved = resolvedLayout
        content(for: resolved)
            .dynamicTypeSize(resolved == .lockScreen ? ActivityTextSize.lockScreen : ActivityTextSize.fixedRegion)
            .environment(\.colorScheme, appearance(for: resolved))
    }

    @ViewBuilder
    private func content(for layout: Layout) -> some View {
        switch layout {
        case .smartStack:
            SmartStackLayout(presentation: presentation)
        case .automatic, .lockScreen, .standBy:
            if presentation.isSolo {
                SoloLayout(presentation: presentation, isStandBy: layout == .standBy)
            } else {
                SquadLayout(presentation: presentation, isStandBy: layout == .standBy)
            }
        }
    }

    /// Never `.automatic`.
    private var resolvedLayout: Layout {
        guard layout == .automatic else { return layout }
        switch activityFamily {
        case .small:
            return .smartStack
        default:
            return isActivityFullscreen ? .standBy : .lockScreen
        }
    }

    /// Dark in StandBy, which is full-bleed black, and in Always-On, which the system draws as if
    /// in Dark Mode; otherwise the system's own. In the dark appearance `.primary` is white and the
    /// state colours take their dark variants, which are made for black. On a phone the system
    /// already draws both dark; the Lab's stand-ins can't be StandBy or Always-On, so they rely on
    /// this.
    private func appearance(for layout: Layout) -> ColorScheme {
        layout == .standBy || isLuminanceReduced ? .dark : colorScheme
    }
}

// MARK: - Squad

/// About 143 points tall at the default text size: 12 + header 20.3 + 8 + row 68.3 + 8 + pet
/// 14.3 + 12. At xLarge, the most the Lock Screen allows, about 152: 12 + 22.7 + 8 + row 73 + 8 +
/// 16.7 + 12. The `largest` sample's emoji names and squad name add a point or two.
///
/// StandBy puts your countdown in the header at 40 points (47.7 tall) and moves the pet up beside
/// it, under the squad name and status: 20.3 + 2 + 15.7 + 14.3 = 52.3, the taller of the two.
/// That keeps it about 153 points: 12 + header 52.3 + 8 + row 68.3 + 12. StandBy holds text at
/// the default size, because the system scales the view up from there, and it truncates past
/// 160 points just as on the Lock Screen (LockScreenHeightTests measures both).
///
/// The row's Locklings are 34 points: large enough for their hats and props, small enough that
/// six fit across an iPhone SE.
private struct SquadLayout: View {
    let presentation: LiveActivityPresentation
    let isStandBy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.s) {
            if isStandBy {
                standByHeader
            } else {
                header
            }
            HStack(alignment: .top, spacing: LKSpacing.xs) {
                ForEach(presentation.lockScreenMembers) { member in
                    MemberColumn(member: member, creatureSize: ActivityMetrics.lockScreenRowCreature)
                }
            }
            .frame(maxWidth: .infinity)
            if !isStandBy, let pet = presentation.pet {
                PetRow(pet: pet)
            }
        }
        .padding(.horizontal, ActivityMetrics.lockScreenMargin)
        .padding(.vertical, LKSpacing.m)
    }

    /// The squad name, and how many are locked in on the same baseline at the trailing edge (or,
    /// while a cheer for you is in, who sent it).
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: LKSpacing.s) {
            title
            Spacer(minLength: LKSpacing.s)
            SquadStatus(text: presentation.statusLine, cheer: presentation.cheerForMe)
                // The count keeps its width; a long squad name truncates instead.
                .layoutPriority(1)
        }
    }

    /// The squad name, status and pet stacked beside your countdown.
    private var standByHeader: some View {
        HStack(alignment: .center, spacing: LKSpacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                    title
                    SquadStatus(text: presentation.statusLine, cheer: presentation.cheerForMe)
                }
                .accessibilityElement(children: .combine)
                if let pet = presentation.pet {
                    PetRow(pet: pet)
                }
            }
            // The width the countdown leaves goes to this column, not the spacer, so the pet's
            // bar and a long squad name aren't squeezed.
            .layoutPriority(1)
            Spacer(minLength: LKSpacing.s)
            if let me = presentation.primary {
                CountdownText(countdown: me.countdown, tone: me.tone, style: ActivityTimer.standBySquad)
                    // Its full width first: the pet's bar beside it would take any it gave up,
                    // and a word ("Done") has no reserved frame to hold it.
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel(me.accessibilityLabel)
                    .accessibilityCountdownValue(me.countdown)
            }
        }
    }

    private var title: some View {
        Text(presentation.headline)
            .font(ActivityFont.headline)
            .foregroundStyle(LKColor.textPrimary)
            .lineLimit(1)
    }
}

// MARK: - Solo

/// Your Lockling beside what you're doing and your countdown, the bar under them, and the buttons
/// under that:
///
///     [Lockling]  Locked in             14:59
///     [        ]  ━━━━━━━━━━━━━━━━━━━━━━━━━━━
///     [        ]  (⏸ Pause)  (✕ End)
///
/// About 100 points tall at the default text size: 12 + the column (title 26.3 + 8 + bar 4 + 8 +
/// small buttons about 28 = 74.3) + 12, the Lockling's 52 centred beside it. About 106 at xLarge.
/// Once the session is over there are no buttons and it's about 76, the Lockling's height.
///
/// StandBy is the "desk mode" shot (SPEC.md §1.7): a big Lockling and the time as the hero, with
/// what you're doing and the bar under them. About 142 points: 12 + timer 85.9 + 12 + headline
/// 20.3 + 12. No buttons there: the phone is on a stand across the desk.
private struct SoloLayout: View {
    let presentation: LiveActivityPresentation
    let isStandBy: Bool

    var body: some View {
        Group {
            if isStandBy {
                standBy
            } else {
                lockScreen
            }
        }
        .padding(.horizontal, ActivityMetrics.lockScreenMargin)
        .padding(.vertical, LKSpacing.m)
    }

    private var lockScreen: some View {
        HStack(alignment: .center, spacing: LKSpacing.m) {
            creature(size: ActivityMetrics.soloCreature)
            VStack(alignment: .leading, spacing: LKSpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: LKSpacing.s) {
                    headline
                        .layoutPriority(1)
                    Spacer(minLength: LKSpacing.s)
                    countdown(style: ActivityTimer.lockScreen)
                }
                progressBar
                if presentation.sessionControls != .hidden {
                    SessionButtons(controls: presentation.sessionControls, fillsWidth: false)
                        .controlSize(.small)
                }
            }
        }
    }

    private var standBy: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            HStack(spacing: LKSpacing.m) {
                creature(size: ActivityMetrics.soloStandByCreature)
                Spacer(minLength: LKSpacing.s)
                if let me = presentation.primary {
                    countdown(style: ActivityTimer.standBySolo(for: me.countdown))
                }
            }
            HStack(spacing: LKSpacing.m) {
                headline
                    .fixedSize()
                progressBar
            }
        }
    }

    @ViewBuilder
    private func creature(size: CGFloat) -> some View {
        if let me = presentation.primary {
            MemberBadge(me, size: size)
        }
    }

    private var headline: some View {
        Text(presentation.headline)
            .font(ActivityFont.headline)
            .foregroundStyle(LKColor.textPrimary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func countdown(style: LKTypeStyle) -> some View {
        if let me = presentation.primary {
            CountdownText(countdown: me.countdown, tone: me.tone, style: style)
                .accessibilityLabel(me.accessibilityLabel)
                .accessibilityCountdownValue(me.countdown)
        }
    }

    private var progressBar: some View {
        SessionProgressBar(
            progress: presentation.sessionProgress,
            tint: presentation.primary?.tone.color ?? LKColor.tint
        )
    }
}

// MARK: - Smart Stack

/// The small activity family: about 160 × 70 points on Apple Watch, with the system's margins
/// around it. You, your time, and how many are locked in (or who cheered you on): about 66
/// points, Lockling 24 + timer 26.3 + status 15.7. No buttons: the HIG keeps them out of the Smart
/// Stack, which CarPlay shares.
private struct SmartStackLayout: View {
    let presentation: LiveActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LKSpacing.s) {
                if let me = presentation.primary {
                    MemberBadge(me, size: ActivityMetrics.smartStackCreature)
                }
                Text(presentation.headline)
                    .font(ActivityFont.status)
                    .fontWeight(.semibold)
                    .foregroundStyle(LKColor.textPrimary)
                    .lineLimit(1)
            }
            if let me = presentation.primary {
                CountdownText(
                    countdown: me.countdown,
                    tone: me.tone,
                    style: ActivityTimer.smartStack,
                    alignment: .leading,
                    sizing: .fill
                )
                .accessibilityLabel(me.accessibilityLabel)
                .accessibilityCountdownValue(me.countdown)
            }
            if !presentation.isSolo {
                SquadStatus(text: presentation.statusLine, cheer: presentation.cheerForMe)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
