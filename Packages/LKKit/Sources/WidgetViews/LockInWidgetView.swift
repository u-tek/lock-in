import AppIntents
import Creature
import DesignSystem
import LiveActivity
import Model
import SwiftUI
import WidgetKit

/// The Lock in widget (small): your Lockling and a Lock in button that starts a 25-minute solo
/// session without opening the app; while a session runs, its countdown instead.
///
/// The button is a `Button(intent:)` with `StartSessionIntent`, a `LiveActivityIntent`: iOS runs
/// it in the app's process, where the session engine starts the session and its Live Activity,
/// writes the widgets' data and reloads them. The countdown is `Text(timerInterval:)`, so it
/// ticks on its own; a paused session shows its time left, which doesn't move.
public struct LockInWidgetView: View {
    private let avatar: AvatarCode
    private let state: LockInWidgetState
    /// The entry's date: where a countdown starts from.
    private let now: Date
    private let isFullColor: Bool
    /// Always-On (StandBy at night, a dimmed Lock Screen): the creatures are outlines already.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(data: WidgetData, now: Date, isFullColor: Bool = true) {
        avatar = data.avatarCode
        state = LockInWidgetState(data: data, now: now)
        self.now = now
        self.isFullColor = isFullColor
    }

    public var body: some View {
        Group {
            switch state {
            case .idle(let todayMinutes):
                IdleLockIn(avatar: avatar, todayMinutes: todayMinutes, isFullColor: isFullColor)
            case .running(let ends, let squadName):
                SessionLockIn(
                    avatar: avatar,
                    pose: .focusing,
                    title: squadName ?? "Locked in",
                    isFullColor: isFullColor
                ) {
                    // Never an inverted range, which would trap: `state` is only running while
                    // `ends` is after `now`.
                    Text(timerInterval: min(now, ends)...ends, countsDown: true)
                }
            case .paused(let remaining, let squadName):
                SessionLockIn(
                    avatar: avatar,
                    pose: .paused,
                    title: squadName.map { "Paused · \($0)" } ?? "Paused",
                    isFullColor: isFullColor
                ) {
                    Text(verbatim: WidgetWords.clock(remaining))
                }
            }
        }
        .environment(\.isLuminanceReduced, isLuminanceReduced || !isFullColor)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// The colour behind the widget (`WidgetSurface`).
    public static var accent: Color {
        LKColor.tint
    }
}

/// The Lockling and today's minutes over the button.
private struct IdleLockIn: View {
    let avatar: AvatarCode
    let todayMinutes: Int
    let isFullColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: LKSpacing.s) {
                CreatureView(avatar: avatar, pose: .idle, size: WidgetMetrics.lockInCreature)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(max(0, todayMinutes))")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("min today")
                        .font(LKFont.caption.weight(.medium))
                        .foregroundStyle(LKColor.textSecondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: WidgetWords.today(todayMinutes)))
            }
            Spacer(minLength: LKSpacing.s)
            Text("25 minutes, solo")
                .font(LKFont.caption.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
                .padding(.bottom, LKSpacing.xs)
            Button(intent: StartSessionIntent()) {
                Label("Lock in", systemImage: "lock.fill")
                    .font(LKFont.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(isFullColor ? LKColor.tint : Color.primary)
            .widgetAccentable()
            .accessibilityHint("Starts a 25-minute session")
        }
    }
}

/// A session going: the Lockling in its pose, what's going on, and the time.
private struct SessionLockIn<Time: View>: View {
    let avatar: AvatarCode
    let pose: CreaturePose
    let title: String
    let isFullColor: Bool
    @ViewBuilder let time: () -> Time

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: LKSpacing.s) {
                CreatureView(avatar: avatar, pose: pose, size: WidgetMetrics.lockInCreature)
                Spacer(minLength: 0)
                Image(systemName: pose == .paused ? "pause.fill" : "lock.fill")
                    .font(LKFont.subheadline.weight(.semibold))
                    .foregroundStyle(isFullColor ? (pose == .paused ? LKColor.paused : LKColor.focusing) : Color.primary)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: LKSpacing.s)
            Text(title)
                .font(LKFont.subheadline.weight(.semibold))
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
            time()
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetAccentable()
        }
    }
}
