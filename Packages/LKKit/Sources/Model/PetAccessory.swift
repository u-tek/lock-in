import Foundation

/// What a boosted squad's pet can wear (M7, Squad Boost, docs/milestones/M7.md): part `pet` of
/// `fixtures/shop/catalogue.json`, `pet.1` to `pet.6`. Any member of a boosted squad picks one
/// (`PATCH /squads/:id/pet`), everyone sees it, and the Live Activity's `Pet.k` carries it as
/// `.a<n>` ("sprout.2.a3"). The `Creature` module draws them, in shapes, on every stage but the egg.
///
/// The numbers are a wire format shared with the server, so they never change and new ones go on
/// the end.
public enum PetAccessory: Int, CaseIterable, Sendable, Identifiable {
    case scarf = 1
    case partyHat = 2
    case flowerCrown = 3
    case glasses = 4
    case bow = 5
    case starClip = 6

    public var id: Int { rawValue }

    /// "Scarf", "Party hat". English only until the app has a string catalogue.
    public var title: String {
        switch self {
        case .scarf: "Scarf"
        case .partyHat: "Party hat"
        case .flowerCrown: "Flower crown"
        case .glasses: "Glasses"
        case .bow: "Bow"
        case .starClip: "Star clip"
        }
    }

    /// Its id in the shop's catalogue: "pet.3".
    public var shopItemID: String {
        "\(Self.shopPart).\(rawValue)"
    }

    /// The catalogue's part for the pet's accessories.
    public static let shopPart = "pet"
}
