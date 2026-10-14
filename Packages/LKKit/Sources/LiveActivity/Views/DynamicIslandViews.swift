import Creature
import DesignSystem
import Model
import SwiftUI

// The Dynamic Island's presentations (SPEC.md §1.3). Each is a plain view over
// `(attributes, state)`, not `ActivityViewContext`, so the widget extension's `DynamicIsland`
// regions and the app's Live Activity Lab draw exactly the same thing. The island is always black
// and the system draws it; these views draw only what sits inside, in the dark appearance
// (`islandAppearance()`), with SF Pro text and the members' system colours.
//
// They follow Apple's island templates (Human Interface Guidelines, Live Activities): no padding
// or frames of our own, so the system's region margins place everything and the compact content
// sits snug against the camera; compact content as narrow as it can be; everything the expanded
// island shows wrapped close round the camera.

/// Compact, left of the camera: your Lockling, in your state's pose.
public struct CompactLeadingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        IslandCreature(member: presentation.primary)
            .islandAppearance()
    }
}

/// Compact, right of the camera: "+3" squadmates focusing, or your own time when solo or when
/// nobody else is focusing. Trailing-aligned with monospaced digits, so it hugs the island's edge
/// and doesn't shuffle as it ticks. While a cheer for you is in, its symbol in its colour instead,
/// at the same size as the text it stands in for.
public struct CompactTrailingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        trailing
            .islandAppearance()
    }

    @ViewBuilder
    private var trailing: some View {
        switch presentation.compactTrailing {
        case .cheer(let cheer):
            CheerSymbol(kind: cheer.kind)
                .font(ActivityTimer.island.font)
                .accessibilityLabel(presentation.compactTrailingAccessibilityLabel)
        case .squadmates(let count):
            Text(verbatim: "+\(count)")
                .font(ActivityTimer.island.font)
                .foregroundStyle(LKMemberTone.focusing.color)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityLabel(presentation.compactTrailingAccessibilityLabel)
        case .countdown(let countdown, let tone):
            // Held to the width of its longest reading: `Text(timerInterval:)` would otherwise
            // take all the width offered and push the island wide.
            CountdownText(countdown: countdown, tone: tone, style: ActivityTimer.island)
                .accessibilityLabel(presentation.compactTrailingAccessibilityLabel)
                .accessibilityCountdownValue(countdown)
        case .empty:
            EmptyView()
        }
    }
}

/// Minimal, when several apps' activities share the island: your Lockling and nothing else. The
/// system centres it.
public struct MinimalView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        IslandCreature(member: presentation.primary)
            .islandAppearance()
    }
}

/// Expanded, left of the camera: your Lockling, larger.
public struct ExpandedLeadingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        IslandCreature(member: presentation.primary, size: ActivityMetrics.expandedCreature)
            .islandAppearance()
    }
}

/// Expanded, right of the camera: your countdown, large, in your state's colour. Its top lines up
/// with the Lockling's beside the other side of the camera.
public struct ExpandedTrailingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        Group {
            if let me = presentation.primary {
                CountdownText(countdown: me.countdown, tone: me.tone, style: ActivityTimer.expanded)
                    .accessibilityLabel(me.accessibilityLabel)
                    .accessibilityCountdownValue(me.countdown)
                    .frame(minHeight: ActivityMetrics.expandedCreature, alignment: .top)
            }
        }
        .islandAppearance()
    }
}

/// Expanded, under the camera: the squad name, or for a solo session what you're doing ("Locked
/// in"). One line. While a cheer for you is in, that line says who sent it instead ("Noor cheered
/// you on", behind the cheer's symbol), in the same type, so the island keeps its height. The
/// region is about 200 points wide between your Lockling and your time, so the words shrink a
/// little before a long name is cut short.
public struct ExpandedCenterView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        Group {
            if let cheer = presentation.cheerForMe {
                CheerLine(cheer: cheer, ink: LKColor.textPrimary)
                    .minimumScaleFactor(0.8)
            } else {
                Text(presentation.headline)
                    .foregroundStyle(LKColor.textPrimary)
                    .lineLimit(1)
            }
        }
        .font(ActivityFont.headline)
        .islandAppearance()
    }
}

/// Expanded, along the bottom. Solo: Pause or Resume, and End, sharing the width. Squad: up to
/// four squadmates as Locklings with their names and times, in equal columns so the row is evenly
/// spaced whoever is in it; anyone past four is on the Lock Screen rather than squeezed in as
/// "+2". Nothing at all once a solo session is over, so the island shrinks to fit.
///
/// The squad row is about 64 points tall (Lockling 30 + 2 + name 14.3 + countdown 18) and the
/// buttons about 34, which with the 44-point Lockling above keeps the island well inside its 160.
/// Text stays at the default size or under (`islandAppearance()`), so those numbers hold.
public struct ExpandedBottomView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        Group {
            if presentation.isSolo {
                SessionButtons(controls: presentation.sessionControls, fillsWidth: true)
                    .controlSize(.regular)
            } else if !presentation.expandedMembers.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(presentation.expandedMembers) { member in
                        MemberColumn(member: member, creatureSize: ActivityMetrics.expandedRowCreature)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .islandAppearance()
    }
}

/// You at island size: your Lockling, a fixed square so the compact and minimal presentations
/// never push the island wider or taller. A plain Lockling before anyone's in the content-state.
private struct IslandCreature: View {
    let member: LiveActivityPresentation.Member?
    var size: CGFloat = ActivityMetrics.islandCreature

    var body: some View {
        if let member {
            MemberBadge(member, size: size)
        } else {
            CreatureView(avatar: .default, pose: .idle, size: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lockin")
        }
    }
}
