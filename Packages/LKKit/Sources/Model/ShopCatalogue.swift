import Foundation

/// One part of a Lockling the shop sells: the parts of an avatar code (`AvatarCode`), by the
/// names the server uses (`ShopItem.part` in docs/milestones/M5.md).
public enum ShopPart: String, Codable, CaseIterable, Sendable, Identifiable {
    case body
    case colour
    case eyes
    case hat

    public var id: String { rawValue }

    /// The option this part is at in an avatar code.
    public func option(in avatar: AvatarCode) -> Int {
        switch self {
        case .body: avatar.body
        case .colour: avatar.colour
        case .eyes: avatar.eyes
        case .hat: avatar.hat
        }
    }

    /// The avatar with this part changed to `option`.
    public func applying(_ option: Int, to avatar: AvatarCode) -> AvatarCode {
        var changed = avatar
        switch self {
        case .body: changed.body = max(0, option)
        case .colour: changed.colour = max(0, option)
        case .eyes: changed.eyes = max(0, option)
        case .hat: changed.hat = max(0, option)
        }
        return changed
    }
}

/// Something the coin shop sells: one option of one part (docs/milestones/M5.md, `ShopItem`).
///
/// The keys are the wire format of `GET /shop`, so a plain `JSONDecoder()` reads the server's
/// items. Defaults (option 0) are never sold: everyone has them.
public struct ShopItem: Codable, Hashable, Sendable, Identifiable {
    /// `<part>.<option>`, e.g. "hat.1": the option is the number in the avatar code, so "hat.3" is
    /// the "h3" of "b0.c0.e0.h3".
    public var id: String
    public var part: ShopPart
    /// Never 0.
    public var option: Int
    /// Coins; 0 for Plus items, which aren't bought but come with Lockin Plus.
    public var price: Int
    /// A Lockin Plus item (SPEC.md §2): yours while Plus lasts, never sold for coins.
    public var plus: Bool

    public init(id: String, part: ShopPart, option: Int, price: Int, plus: Bool) {
        self.id = id
        self.part = part
        self.option = option
        self.price = price
        self.plus = plus
    }

    /// The id of a part's option: "hat.3".
    public static func id(part: ShopPart, option: Int) -> String {
        "\(part.rawValue).\(option)"
    }

    /// The avatar wearing this item.
    public func applied(to avatar: AvatarCode) -> AvatarCode {
        part.applying(option, to: avatar)
    }

    /// The avatar has this item on.
    public func isWorn(by avatar: AvatarCode) -> Bool {
        part.option(in: avatar) == option
    }
}

/// Everything the coin shop sells, in the server's order: a copy of
/// `fixtures/shop/catalogue.json` at the repository root, which the server sells from. `ModelTests`
/// checks this copy against the file, so change both together.
///
/// The app shows the shop from this list, signed in or out, and counts what's bought signed out
/// against it; `GET /shop` says the same thing.
public enum ShopCatalogue {
    public static let items: [ShopItem] = [
        ShopItem(id: "body.1", part: .body, option: 1, price: 120, plus: false),
        ShopItem(id: "body.2", part: .body, option: 2, price: 150, plus: false),
        ShopItem(id: "body.3", part: .body, option: 3, price: 180, plus: false),
        ShopItem(id: "body.4", part: .body, option: 4, price: 0, plus: true),
        ShopItem(id: "colour.1", part: .colour, option: 1, price: 40, plus: false),
        ShopItem(id: "colour.2", part: .colour, option: 2, price: 45, plus: false),
        ShopItem(id: "colour.3", part: .colour, option: 3, price: 50, plus: false),
        ShopItem(id: "colour.4", part: .colour, option: 4, price: 50, plus: false),
        ShopItem(id: "colour.5", part: .colour, option: 5, price: 60, plus: false),
        ShopItem(id: "colour.6", part: .colour, option: 6, price: 0, plus: true),
        ShopItem(id: "colour.7", part: .colour, option: 7, price: 0, plus: true),
        ShopItem(id: "eyes.1", part: .eyes, option: 1, price: 60, plus: false),
        ShopItem(id: "eyes.2", part: .eyes, option: 2, price: 70, plus: false),
        ShopItem(id: "eyes.3", part: .eyes, option: 3, price: 0, plus: true),
        ShopItem(id: "eyes.4", part: .eyes, option: 4, price: 80, plus: false),
        ShopItem(id: "hat.1", part: .hat, option: 1, price: 80, plus: false),
        ShopItem(id: "hat.2", part: .hat, option: 2, price: 0, plus: true),
        ShopItem(id: "hat.3", part: .hat, option: 3, price: 100, plus: false),
        ShopItem(id: "hat.4", part: .hat, option: 4, price: 120, plus: false),
        ShopItem(id: "hat.5", part: .hat, option: 5, price: 0, plus: true),
    ]

    public static func item(id: String) -> ShopItem? {
        items.first { $0.id == id }
    }

    public static func item(part: ShopPart, option: Int) -> ShopItem? {
        item(id: ShopItem.id(part: part, option: option))
    }

    /// One part's items, cheapest first (the catalogue's own order within a part).
    public static func items(for part: ShopPart) -> [ShopItem] {
        items.filter { $0.part == part }
    }

    /// The items an avatar wears that coins can buy: what it has on beyond the defaults, Plus items
    /// left out. The app counts these as yours when it first sees the shop, since every free part
    /// was free before it (docs/milestones/M5.md, "As built (app)").
    public static func freeItemIDs(wornBy avatar: AvatarCode) -> [String] {
        items.filter { !$0.plus && $0.isWorn(by: avatar) }.map(\.id)
    }
}
