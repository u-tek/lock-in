import DesignSystem
import Model
import SwiftUI

// The Dynamic Island's presentations (SPEC.md §1.3). Each is a plain view over
// `(attributes, state)`, not `ActivityViewContext`, so the widget extension's `DynamicIsland`
// regions and the app's Live Activity Lab draw exactly the same thing. The island is always black
// and the system draws it; these views draw only what sits inside, in the dark appearance
// (`islandAppearance()`), with SF Pro text and the members' system colours.

/// Compact, left of the camera: you, as a disc in your state's colour carrying its symbol.
public struct CompactLeadingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        IslandBadge(member: presentation.primary)
            .islandAppearance()
    }
}

/// Compact, right of the camera: "+3" squadmates focusing, or your own time when solo or when
/// nobody else is focusing.
public struct CompactTrailingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        trailing
            .frame(height: ActivityMetrics.islandBadge)
            .islandAppearance()
    }

    @ViewBuilder
    private var trailing: some View {
        switch presentation.compactTrailing {
        case .squadmates(let count):
            Text(verbatim: "+\(count)")
                .font(ActivityTimer.island.font)
                .foregroundStyle(LKMemberTone.focusing.color)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityLabel(presentation.compactTrailingAccessibilityLabel)
        case .countdown(let countdown, let tone):
            CountdownText(countdown: countdown, tone: tone, style: ActivityTimer.island)
                .accessibilityLabel(presentation.compactTrailingAccessibilityLabel)
                .accessibilityCountdownValue(countdown)
        case .empty:
            EmptyView()
        }
    }
}

/// Minimal, when several apps' activities share the island: you, and nothing else.
public struct MinimalView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        IslandBadge(member: presentation.primary)
            .islandAppearance()
    }
}

/// Expanded, left of the camera: you, larger.
public struct ExpandedLeadingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        Group {
            if let me = presentation.primary {
                MemberBadge(me, size: ActivityMetrics.expandedBadge)
            }
        }
        .islandAppearance()
    }
}

/// Expanded, right of the camera: your countdown, in your state's colour.
public struct ExpandedTrailingView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        Group {
            if let me = presentation.primary {
                CountdownText(countdown: me.countdown, tone: me.tone, style: ActivityTimer.island)
                    .accessibilityLabel(me.accessibilityLabel)
                    .accessibilityCountdownValue(me.countdown)
            }
        }
        .islandAppearance()
    }
}

/// Expanded, under the camera: the squad name and how many are locked in, or for a solo session
/// what you're doing.
public struct ExpandedCenterView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        VStack(spacing: LKSpacing.xxs) {
            Text(presentation.headline)
                .font(ActivityFont.headline)
                .foregroundStyle(LKColor.textPrimary)
            Text(presentation.statusLine)
                .font(ActivityFont.status)
                .foregroundStyle(LKColor.textSecondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .islandAppearance()
    }
}

/// Expanded, along the bottom: up to four squadmates with names and countdowns, "+N" for the
/// rest, and the pet's progress. Solo, or before anyone else has joined, your session's bar.
///
/// About 55 points tall with a full row and a pet (chips 32.3 + 8 + pet 14.3). M1 adds Pause, End
/// and Cheer (`LiveActivityIntent` buttons) under the pet row; that height leaves room for one
/// row of them inside the expanded island's 160 points. Text stays at the default size or under
/// (`islandAppearance()`), so those numbers hold.
public struct ExpandedBottomView: View {
    private let presentation: LiveActivityPresentation

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        presentation = LiveActivityPresentation(attributes: attributes, state: state)
    }

    public var body: some View {
        VStack(spacing: LKSpacing.s) {
            if presentation.expandedMembers.isEmpty {
                SessionProgressBar(
                    progress: presentation.sessionProgress,
                    tint: presentation.primary?.tone.color ?? LKColor.tint
                )
            } else {
                HStack(spacing: LKSpacing.s) {
                    ForEach(presentation.expandedMembers) { member in
                        MemberChip(member: member)
                    }
                    if presentation.expandedOverflow > 0 {
                        OverflowLabel(count: presentation.expandedOverflow)
                    }
                }
            }
            if let pet = presentation.pet {
                PetRow(pet: pet)
            }
        }
        .islandAppearance()
    }
}

/// You at island size, held to a fixed square so the compact and minimal presentations never
/// push the island wider or taller. A lock in the tint before anyone's in the content-state.
private struct IslandBadge: View {
    let member: LiveActivityPresentation.Member?

    var body: some View {
        Group {
            if let member {
                MemberBadge(member, size: ActivityMetrics.islandBadge)
            } else {
                Image(systemName: LKMemberTone.focusing.symbolName)
                    .font(.system(size: ActivityMetrics.islandBadge * 0.6, weight: .bold))
                    .foregroundStyle(LKColor.tint)
                    .accessibilityLabel("Lockin")
            }
        }
        .frame(width: ActivityMetrics.islandBadge, height: ActivityMetrics.islandBadge)
    }
}
