import Core
import Foundation
import Model

// The coin shop's JSON (docs/milestones/M5.md): `GET /shop`, `POST /shop/buy`, `GET /me/cosmetics`
// and `POST /me/coins/import`, shaped like server/src/shop.ts and server/src/accounts.ts. The items
// themselves are `Model`'s `ShopItem`, which the app's own catalogue uses too.

// MARK: - Request bodies

/// `POST /shop/buy`.
struct BuyRequest: Encodable, Sendable {
    var itemId: String
}

/// `POST /me/coins/import`: what this phone earned and bought signed out.
struct CoinsImportRequest: Encodable, Sendable {
    var coins: Int
    var owned: [String]
}

// MARK: - Response envelopes

/// `GET /shop`: `{ items: [ShopItem] }`. An item this build can't read (a part a newer server
/// added) is skipped rather than failing the whole shop.
struct ShopEnvelope: Decodable {
    var items: [ShopItem]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([LenientItem].self, forKey: .items).compactMap(\.item)
    }

    private struct LenientItem: Decodable {
        var item: ShopItem?

        init(from decoder: any Decoder) throws {
            item = try? ShopItem(from: decoder)
        }
    }
}

/// `POST /shop/buy`: the balance after paying, and everything you may now wear.
struct PurchaseResponse: Decodable {
    var coins: Int
    var owned: [String]
}

/// `GET /me/cosmetics`.
struct OwnedEnvelope: Decodable {
    var owned: [String]
}

/// `POST /me/coins/import`: the account with the coins added, and what it owns now.
struct CoinsImportResponse: Decodable {
    var user: User
    var owned: [String]
}
