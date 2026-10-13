import DesignSystem
import SwiftUI

/// A squad member as a monogram, like Contacts and Find My (design/SYSTEM.md): a circle filled
/// with their state's colour as a gradient, their initial in white, and a small status badge
/// carrying the state's symbol. The `Creature` module replaces the monogram in M1 with the
/// member's creature in the state's pose; the sizes, the status badge and the Always-On rule
/// carry over.
///
/// Colour is never the only cue: every state has its own symbol (`LKMemberTone.symbolName`).
/// Under `symbolOnlyBelow` points (the compact and minimal island, the expanded island's chips)
/// a status badge would be too small to read, so the state's symbol takes the initial's place
/// instead. That's "your creature in its current state" (SPEC.md §1.3) until creatures exist.
///
/// It draws no background of its own, so it sits on whatever the presentation shows: the Lock
/// Screen's default background in either appearance, the island's black. That's why the status
/// badge is cut out of the monogram with a clear gap, rather than ringed in a background colour
/// that would never quite match the Lock Screen's.
public struct MemberBadge: View {
    /// Below this size the badge shows the state's symbol alone.
    public nonisolated static let symbolOnlyBelow: CGFloat = MemberBadgeGeometry.symbolOnlyBelow

    private let member: LiveActivityPresentation.Member
    private let size: CGFloat
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(_ member: LiveActivityPresentation.Member, size: CGFloat) {
        self.member = member
        self.size = size
    }

    public var body: some View {
        let geometry = MemberBadgeGeometry(size: size)
        ZStack(alignment: .bottomTrailing) {
            if geometry.showsStatusBadge {
                monogram(geometry)
                statusBadge(geometry)
            } else {
                stateDisc(geometry)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.accessibilityLabel)
    }

    /// White on the colour's fill. Under Always-On there is no fill, so the glyphs take the primary
    /// text style (white, since Always-On is drawn dark) and the state's colour stays on the
    /// outline. Drawn in the colour itself, they would be too dim at this size: small text in dark
    /// indigo is under 4.5:1 on black even before the system dims the screen.
    private var ink: AnyShapeStyle {
        isLuminanceReduced ? AnyShapeStyle(LKColor.textPrimary) : AnyShapeStyle(Color.white)
    }

    /// The circle and the initial, with the status badge's notch cut out of both. The notch cuts
    /// the initial too, as the system's badges cut through a contact's photo, so a wide initial
    /// (an "M", an emoji) never shows in the gap.
    private func monogram(_ geometry: MemberBadgeGeometry) -> some View {
        ZStack {
            // Always-On: an outline rather than a fill, so the dimmed Lock Screen doesn't glow.
            if isLuminanceReduced {
                Circle().strokeBorder(member.tone.color, lineWidth: geometry.outlineWidth)
            } else {
                Circle().fill(member.tone.color.gradient)
            }
            // SF Rounded: the one place it's allowed, because Contacts' monograms use it.
            Text(member.initial)
                .font(.system(size: geometry.initialSize, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: geometry.initialMaxWidth)
        }
        .frame(width: geometry.size, height: geometry.size)
        .mask {
            Rectangle().subtracting(Notch(frame: geometry.notch))
        }
    }

    /// The state's symbol in a small disc of the state's colour, in the monogram's notch. Under
    /// Always-On, the symbol alone in the primary style; the monogram's outline carries the colour.
    private func statusBadge(_ geometry: MemberBadgeGeometry) -> some View {
        ZStack {
            if !isLuminanceReduced {
                Circle().fill(member.tone.color.gradient)
            }
            stateSymbol(size: geometry.symbolSize)
        }
        .frame(width: geometry.statusDiameter, height: geometry.statusDiameter)
    }

    /// Below `symbolOnlyBelow`: the state's symbol on the whole circle.
    private func stateDisc(_ geometry: MemberBadgeGeometry) -> some View {
        ZStack {
            if isLuminanceReduced {
                Circle().strokeBorder(member.tone.color, lineWidth: geometry.outlineWidth)
            } else {
                Circle().fill(member.tone.color.gradient)
            }
            stateSymbol(size: geometry.symbolSize)
        }
    }

    private func stateSymbol(size: CGFloat) -> some View {
        Image(systemName: member.tone.symbolName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(ink)
            // A content transition, which Live Activities do animate: when a state changes, its
            // symbol swaps the way the system's own do.
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Where everything in a monogram `size` points square sits. Worked out here rather than in the
/// body so the tests can check it at every size the presentations draw.
struct MemberBadgeGeometry: Equatable {
    /// The island's and the Smart Stack's monograms, 24 points and under, would carry a status
    /// badge of 9 points or less, too small for its symbol to read.
    static let symbolOnlyBelow: CGFloat = 26

    let size: CGFloat

    var showsStatusBadge: Bool {
        size >= Self.symbolOnlyBelow
    }

    /// The status badge's diameter: a little under two-fifths of the monogram, about the
    /// proportion of the system's own status badges. 13 points on the Lock Screen's 34-point row.
    var statusDiameter: CGFloat {
        (size * 0.38).rounded()
    }

    /// The clear ring between the status badge and the monogram, to the half point: enough to
    /// read as two shapes, as in the system's own badges.
    var gap: CGFloat {
        max(1.5, (size * 0.05 * 2).rounded() / 2)
    }

    /// The status badge, in the bottom-trailing corner of the monogram's square. Inside the
    /// frame, not hanging off it, so the size the layout measures is the size drawn and a
    /// neighbour in the row never runs into it.
    var statusFrame: CGRect {
        CGRect(x: size - statusDiameter, y: size - statusDiameter, width: statusDiameter, height: statusDiameter)
    }

    /// The notch cut out of the monogram for the status badge: its frame and the gap around it.
    var notch: CGRect {
        statusFrame.insetBy(dx: -gap, dy: -gap)
    }

    /// The initial: two-fifths of the circle, about Contacts' size, and small enough that a
    /// capital clears the notch.
    var initialSize: CGFloat {
        size * 0.4
    }

    /// A wide initial (an emoji, "W") shrinks rather than meeting the circle's edge.
    var initialMaxWidth: CGFloat {
        size * 0.7
    }

    /// The state's symbol: just over half the status badge, or half the whole circle when it
    /// stands alone. Wide symbols (`hand.wave.fill`, `cup.and.saucer.fill`) still fit.
    var symbolSize: CGFloat {
        showsStatusBadge ? statusDiameter * 0.55 : size * 0.5
    }

    /// Always-On's outline.
    var outlineWidth: CGFloat {
        max(1.5, size * 0.05)
    }
}

/// A circle at a fixed place in the monogram's frame: the notch `subtracting(_:)` cuts out of the
/// monogram's mask. The frame is in the monogram's coordinates; the rect it's drawn in is that
/// same square, so its origin is the only adjustment.
private struct Notch: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: frame.offsetBy(dx: rect.minX, dy: rect.minY))
    }
}
