import DesignSystem
import SwiftUI

/// A squad member at spike grade: a circle in their state's colour with their initial and the
/// state's symbol. The `Creature` module replaces it in M1 with the member's creature in the
/// state's pose; the sizes and the Always-On rule carry over.
///
/// Colour is never the only cue: every state has its own symbol (`LKMemberTone.symbolName`).
/// Under `symbolOnlyBelow` points (the compact and minimal island) a symbol in the corner would be
/// unreadable, so the state's symbol takes the initial's place instead. That's "your creature in
/// its current state" (SPEC.md §1.3) until creatures exist.
///
/// Draw it inside the night appearance (`lkNightAppearance()`, which every presentation view
/// applies): the state colours are tuned for the activity's dark background.
public struct MemberBadge: View {
    /// Below this size the badge shows the state's symbol alone.
    public static let symbolOnlyBelow: CGFloat = 26

    private let member: LiveActivityPresentation.Member
    private let size: CGFloat
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(_ member: LiveActivityPresentation.Member, size: CGFloat) {
        self.member = member
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Always-On: an outline rather than a fill, so the dimmed Lock Screen doesn't glow.
            if isLuminanceReduced {
                Circle().strokeBorder(member.tone.color, lineWidth: max(1.5, size * 0.07))
            } else {
                Circle().fill(member.tone.color)
            }
            centre
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showsCornerSymbol {
                cornerSymbol
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.accessibilityLabel)
    }

    private var showsCornerSymbol: Bool {
        size >= Self.symbolOnlyBelow
    }

    /// Dark ink on a fill (every state colour is light in the dark appearance); the state's
    /// colour on an outline.
    private var ink: Color {
        isLuminanceReduced ? member.tone.color : LKColor.onAccent
    }

    @ViewBuilder
    private var centre: some View {
        if showsCornerSymbol {
            Text(member.initial)
                .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: size * 0.78)
        } else {
            Image(systemName: member.tone.symbolName)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(ink)
        }
    }

    /// The state's symbol on a disc of the activity's background, overlapping the badge's edge.
    private var cornerSymbol: some View {
        let diameter = (size * 0.42).rounded()
        return ZStack {
            Circle().fill(LKColor.liveActivityBackground)
            Image(systemName: member.tone.symbolName)
                .font(.system(size: diameter * 0.55, weight: .bold))
                .foregroundStyle(member.tone.color)
        }
        .frame(width: diameter, height: diameter)
        .offset(x: size * 0.06, y: size * 0.06)
    }
}
