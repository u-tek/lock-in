import SwiftUI

/// How each member state looks: a colour, a symbol and a word.
///
/// Colour is never the only cue. Every state also has its own symbol (and from M1 its own
/// creature pose), so a squadmate who can't tell two colours apart can still tell the states
/// apart. The colours themselves are chosen to stay apart under the common colour-vision
/// deficiencies; DesignSystemTests checks that.
///
/// Raw values are the wire values of `Member.s` (SPEC.md §4.3) and of Model's `MemberState`, so
/// `LKMemberTone(rawValue: state.rawValue)` maps straight across. DesignSystem doesn't import
/// Model; a state this build doesn't know comes back nil, and callers should draw it as `left`.
public enum LKMemberTone: Int, CaseIterable, Sendable, Identifiable {
    case focusing = 0
    case onBreak = 1
    case paused = 2
    case done = 3
    case left = 4
    case slipped = 5

    public var id: Int { rawValue }

    public var token: LKColorToken {
        switch self {
        case .focusing: LKPalette.focusing
        case .onBreak: LKPalette.onBreak
        case .paused: LKPalette.paused
        case .done: LKPalette.done
        case .left: LKPalette.left
        case .slipped: LKPalette.slipped
        }
    }

    public var color: Color {
        switch self {
        case .focusing: LKColor.focusing
        case .onBreak: LKColor.onBreak
        case .paused: LKColor.paused
        case .done: LKColor.done
        case .left: LKColor.left
        case .slipped: LKColor.slipped
        }
    }

    /// An SF Symbol that names the state without colour. All of them exist on iOS 18.
    public var symbolName: String {
        switch self {
        case .focusing: "lock.fill"
        case .onBreak: "cup.and.saucer.fill"
        case .paused: "pause.fill"
        case .done: "checkmark"
        case .left: "hand.wave.fill"
        case .slipped: "drop.fill"
        }
    }

    /// The state in a word or two, for pills and VoiceOver. English only until the app has a
    /// string catalogue.
    public var title: String {
        switch self {
        case .focusing: "Focusing"
        case .onBreak: "On a break"
        case .paused: "Paused"
        case .done: "Done"
        case .left: "Left"
        case .slipped: "Slipped"
        }
    }
}
