/// The eight cheers, as carried in `Cheer.k` (0–7; the server answers 422 `cheer_invalid` to
/// anything else): SF Symbols, each in its own system colour (`LKColor.cheer(_:)` in
/// DesignSystem, which doesn't import Model). The app's cheer picker lists them in this order and
/// the Live Activity draws the one sent to you.
///
/// The order is the wire format: never reorder, only add at the end.
public enum CheerKind: Int, CaseIterable, Identifiable, Sendable {
    case applause = 0
    case fire = 1
    case star = 2
    case heart = 3
    case lightning = 4
    case thumbsUp = 5
    case party = 6
    case sparkles = 7

    /// A kind from a newer app shows as sparkles rather than nothing.
    public init(kind: Int) {
        self = CheerKind(rawValue: kind) ?? .sparkles
    }

    public var id: Int { rawValue }

    /// The filled symbol. All exist on iOS 17 and later.
    public var symbolName: String {
        switch self {
        case .applause: "hands.clap.fill"
        case .fire: "flame.fill"
        case .star: "star.fill"
        case .heart: "heart.fill"
        case .lightning: "bolt.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .party: "party.popper.fill"
        case .sparkles: "sparkles"
        }
    }

    /// The same symbol without its fill, for Always-On, where nothing glows. Sparkles has no
    /// filled form, so it's the same either way.
    public var outlineSymbolName: String {
        switch self {
        case .applause: "hands.clap"
        case .fire: "flame"
        case .star: "star"
        case .heart: "heart"
        case .lightning: "bolt"
        case .thumbsUp: "hand.thumbsup"
        case .party: "party.popper"
        case .sparkles: "sparkles"
        }
    }

    /// The cheer in a word or two, for VoiceOver. English only until the app has a string
    /// catalogue, like `LKMemberTone.title`.
    public var title: String {
        switch self {
        case .applause: "Applause"
        case .fire: "Fire"
        case .star: "Star"
        case .heart: "Heart"
        case .lightning: "Lightning"
        case .thumbsUp: "Thumbs up"
        case .party: "Party"
        case .sparkles: "Sparkles"
        }
    }
}

extension LockinAttributes.ContentState.Cheer {
    /// `k` as a cheer this build can draw: one it doesn't know is sparkles.
    public var kind: CheerKind {
        CheerKind(kind: k)
    }
}
