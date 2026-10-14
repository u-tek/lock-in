import Model

/// What a Lockling is doing. Every member state has its own pose (SPEC.md §1.3), so a squadmate
/// reads at a glance even at 20 points in the island, where colour alone wouldn't do.
///
/// The shackle is the Lockling's hair: closed while it's locked in (focusing, paused), popped
/// open when it isn't (a break, done, celebrating, left), and just ajar when it slipped.
public enum CreaturePose: String, CaseIterable, Sendable {
    /// Not in a session: Home, onboarding, the paywall.
    case idle
    /// Peeking over a book, eyes down.
    case focusing
    /// Shackle open, a mug of something warm.
    case onBreak
    /// Eyes shut, a couple of z's.
    case paused
    /// Shackle open, a big smile and a sparkle.
    case done
    /// Greyed out and waving goodbye.
    case left
    /// Worried brows, a wobbly mouth and a sweat drop (Deep Focus, M8).
    case slipped
    /// Arms up, mouth open, confetti: a finished session in the app.
    case celebrating

    /// One-to-one, written out so a state added to Model fails to compile here rather than
    /// drawing as something else.
    public init(_ state: MemberState) {
        switch state {
        case .focusing: self = .focusing
        case .onBreak: self = .onBreak
        case .paused: self = .paused
        case .done: self = .done
        case .left: self = .left
        case .slipped: self = .slipped
        }
    }

    /// How far the shackle pops: 0 locked, 1 fully open.
    var shackleOpening: Double {
        switch self {
        case .idle, .focusing, .paused: 0
        case .onBreak, .done, .left, .celebrating: 1
        case .slipped: 0.35
        }
    }

    /// For VoiceOver when the creature stands alone. English only until the app has a string
    /// catalogue; the Live Activity labels members itself.
    var spokenName: String {
        switch self {
        case .idle: "Lockling"
        case .focusing: "Lockling, focusing"
        case .onBreak: "Lockling, on a break"
        case .paused: "Lockling, paused"
        case .done: "Lockling, done"
        case .left: "Lockling, left"
        case .slipped: "Lockling, slipped"
        case .celebrating: "Lockling, celebrating"
        }
    }
}
