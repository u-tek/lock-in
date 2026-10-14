import Model
import SwiftUI

/// The squad pet's species (`PetRules.species`), each an original little creature drawn in shapes
/// by `PetView`. None of them is a padlock: a pet should never be mistaken for a squadmate's
/// Lockling.
///
/// The names are a wire format (`Pet.k`, `squads.pet_species`), shared with the server through
/// `fixtures/pet/rules.json`, so a species' name never changes and new ones go on the end.
public enum PetSpecies: String, CaseIterable, Sendable {
    /// A small cloud with a scalloped top. Grows more puffs, and a wisp of its own as an adult.
    case puff
    /// A round seed with a sprout on top: two leaves, then three, then four and a flower.
    case sprout
    /// A friendly flame with a bright heart where its face is. Grows from one tip to three.
    case ember
    /// A smooth river stone. Grows amethyst crystals: one as a teen, a cluster as an adult.
    case pebble

    /// A species from its wire name. One this version doesn't know (a newer server's) draws as a
    /// puff, so an old app never fails to show the squad's pet.
    public init(name: String) {
        self = PetSpecies(rawValue: name.lowercased()) ?? .puff
    }

    /// For headings: "Puff". English only until the app has a string catalogue.
    public var title: String {
        switch self {
        case .puff: "Puff"
        case .sprout: "Sprout"
        case .ember: "Ember"
        case .pebble: "Pebble"
        }
    }

    // MARK: - Drawing

    /// The body's frame as an adult, in fractions of the pet's square: width and height. Leaves
    /// and crystals stand above it, flame tips are part of it.
    var proportions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .puff: (0.90, 0.60)
        case .sprout: (0.66, 0.58)
        case .ember: (0.64, 0.86)
        case .pebble: (0.88, 0.58)
        }
    }

    /// Where the face sits, in fractions of the body's frame: the eyes' height from the top, and
    /// each eye's distance from the middle.
    var facePlacement: (eyes: CGFloat, spread: CGFloat) {
        switch self {
        case .puff: (0.56, 0.17)
        case .sprout: (0.50, 0.21)
        case .ember: (0.66, 0.20)
        case .pebble: (0.48, 0.17)
        }
    }

    /// The soft sheen on the body, in fractions of its frame: x, y, width and height.
    var highlight: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        switch self {
        case .puff: (0.20, 0.34, 0.16, 0.10)
        case .sprout: (0.18, 0.22, 0.16, 0.12)
        case .ember: (0.14, 0.48, 0.10, 0.14)
        case .pebble: (0.16, 0.16, 0.20, 0.10)
        }
    }

    /// System colours only (design/SYSTEM.md), so each follows light and dark mode, and the
    /// island draws the dark variant. Softer than the Locklings' and none of them indigo, so the
    /// pet reads as the squad's rather than as one more member.
    var bodyColour: Color {
        switch self {
        case .puff: Color.cyan.mix(with: .white, by: 0.45)
        case .sprout: Color.green.mix(with: .yellow, by: 0.3).mix(with: .white, by: 0.22)
        case .ember: Color.orange
        case .pebble: Color.gray.mix(with: .brown, by: 0.35).mix(with: .white, by: 0.12)
        }
    }

    /// What grows on it: the puff's wisp, the sprout's leaves, the ember's bright heart, the
    /// pebble's crystals.
    var partColour: Color {
        switch self {
        case .puff: Color.cyan.mix(with: .white, by: 0.62)
        case .sprout: Color.green.mix(with: .black, by: 0.06)
        case .ember: Color.yellow
        case .pebble: Color.purple.mix(with: .white, by: 0.15)
        }
    }

    /// Spots on the egg (and the pebble's flecks): the species' colour at full strength, so the
    /// egg hints at what will hatch before anyone knows.
    var speckleColour: Color {
        switch self {
        case .puff: Color.cyan
        case .sprout: Color.green
        case .ember: Color.orange.mix(with: .red, by: 0.3)
        case .pebble: bodyColour.mix(with: .black, by: 0.25)
        }
    }
}
