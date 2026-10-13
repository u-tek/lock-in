import SwiftUI

/// How each member state looks: a system colour, a symbol and a word (design/SYSTEM.md).
///
/// Colour is never the only cue. Every state also has its own symbol (and from M1 its own
/// creature pose), so a squadmate who can't tell two colours apart can still tell the states
/// apart. The system colours aren't ours to tune for colour-vision deficiencies, which is one
/// more reason the symbol has to carry the meaning on its own.
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

    /// The catalogue entry behind `color`, for the tokens page and the tests.
    public var token: LKColorToken {
        switch self {
        case .focusing: LKColorCatalogue.focusing
        case .onBreak: LKColorCatalogue.onBreak
        case .paused: LKColorCatalogue.paused
        case .done: LKColorCatalogue.done
        case .left: LKColorCatalogue.left
        case .slipped: LKColorCatalogue.slipped
        }
    }

    /// Indigo, teal, orange, green, grey or pink. The Dynamic Island is always dark, and these
    /// resolve to their dark variants there by themselves.
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

    /// The state in a word or two, for status lines and VoiceOver. English only until the app
    /// has a string catalogue.
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
