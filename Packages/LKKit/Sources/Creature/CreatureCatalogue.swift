import SwiftUI

/// One choice for one part of a Lockling: a body, a colour, eyes or a hat.
public struct CreatureOption: Identifiable, Hashable, Sendable {
    /// The number in the avatar code (`AvatarCode`): "b3" is body 3.
    public let id: Int
    public let name: String
    /// A Lockin Plus cosmetic (SPEC.md §2). Everything else is free.
    public let isPlus: Bool

    public init(id: Int, name: String, isPlus: Bool = false) {
        self.id = id
        self.name = name
        self.isPlus = isPlus
    }
}

/// Every part a Lockling can wear, in avatar-code order. Ids run from 0 with no gaps, and 0 is
/// each part's free default.
///
/// The ids are a wire format: other members' codes arrive in the Live Activity, so an option's id
/// never changes and new options go on the end. A code from a newer app version may name an id
/// this list doesn't have yet; the creature draws that part as the default (SPEC.md §5.3).
public enum CreatureCatalogue {
    public static let bodies: [CreatureOption] = LocklingBody.allCases.map {
        CreatureOption(id: $0.rawValue, name: $0.name, isPlus: $0.isPlus)
    }

    public static let colours: [CreatureOption] = LocklingColour.allCases.map {
        CreatureOption(id: $0.rawValue, name: $0.name, isPlus: $0.isPlus)
    }

    public static let eyes: [CreatureOption] = LocklingEyes.allCases.map {
        CreatureOption(id: $0.rawValue, name: $0.name, isPlus: $0.isPlus)
    }

    public static let hats: [CreatureOption] = LocklingHat.allCases.map {
        CreatureOption(id: $0.rawValue, name: $0.name, isPlus: $0.isPlus)
    }

    /// The colour a body is drawn in: a system colour, so it follows light and dark mode and the
    /// island draws its dark variant. Unknown ids get the default, indigo.
    public static func colour(_ id: Int) -> Color {
        LocklingColour(id: id).color
    }
}

// MARK: - Parts

/// Lock shapes. The shackle sits a little narrower on wide bodies and wider on tall ones, so each
/// keeps a padlock's proportions.
enum LocklingBody: Int, CaseIterable, Sendable {
    case classic, round, tall, chunky, heart

    init(id: Int) {
        self = LocklingBody(rawValue: id) ?? .classic
    }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .round: "Round"
        case .tall: "Tall"
        case .chunky: "Chunky"
        case .heart: "Heart"
        }
    }

    var isPlus: Bool {
        self == .heart
    }

    /// Fractions of the frame: width, height and corner radius, and the shackle's half-width as a
    /// fraction of the body's width. The heart draws its own outline and ignores the radius.
    var proportions: (width: CGFloat, height: CGFloat, cornerRadius: CGFloat, shackleSpread: CGFloat) {
        switch self {
        case .classic: (0.68, 0.50, 0.15, 0.30)
        case .round: (0.64, 0.54, 0.27, 0.29)
        case .tall: (0.54, 0.56, 0.14, 0.31)
        case .chunky: (0.80, 0.46, 0.16, 0.27)
        case .heart: (0.70, 0.56, 0, 0.24)
        }
    }
}

/// System colours only (design/SYSTEM.md). Grey is kept back for members who left.
enum LocklingColour: Int, CaseIterable, Sendable {
    case indigo, blue, teal, mint, green, orange, pink, purple

    init(id: Int) {
        self = LocklingColour(rawValue: id) ?? .indigo
    }

    var name: String {
        switch self {
        case .indigo: "Indigo"
        case .blue: "Blue"
        case .teal: "Teal"
        case .mint: "Mint"
        case .green: "Green"
        case .orange: "Orange"
        case .pink: "Pink"
        case .purple: "Purple"
        }
    }

    var isPlus: Bool {
        self == .pink || self == .purple
    }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .mint: .mint
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        }
    }
}

enum LocklingEyes: Int, CaseIterable, Sendable {
    case dots, happy, sleepy, sparkly, wink

    init(id: Int) {
        self = LocklingEyes(rawValue: id) ?? .dots
    }

    var name: String {
        switch self {
        case .dots: "Dots"
        case .happy: "Happy"
        case .sleepy: "Sleepy"
        case .sparkly: "Sparkly"
        case .wink: "Wink"
        }
    }

    var isPlus: Bool {
        self == .sparkly
    }
}

/// Hats sit on the shackle and move with it when it pops open. Below
/// `LocklingGeometry.detailFrom` points they're left off: too small to read, and the lock is
/// better off with the room.
enum LocklingHat: Int, CaseIterable, Sendable {
    // Not `none`, which would read as `Optional.none` wherever a hat is optional.
    case noHat, beanie, headphones, cap, flower, crown

    init(id: Int) {
        self = LocklingHat(rawValue: id) ?? .noHat
    }

    var name: String {
        switch self {
        case .noHat: "None"
        case .beanie: "Beanie"
        case .headphones: "Headphones"
        case .cap: "Cap"
        case .flower: "Flower"
        case .crown: "Crown"
        }
    }

    var isPlus: Bool {
        self == .headphones || self == .crown
    }
}
