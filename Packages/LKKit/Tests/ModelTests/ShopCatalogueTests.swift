import Foundation
import Testing
@testable import Model

/// `fixtures/shop/catalogue.json` at the repository root: what the shop sells, which the server
/// sells from (docs/milestones/M5.md). `ShopCatalogue.items` is the app's copy of it.
enum ShopCatalogueFixture {
    struct File: Decodable {
        let items: [ShopItem]
    }

    /// Walks up from this source file to the directory holding `fixtures/shop`, as `Fixture` does
    /// for the Live Activity's.
    static func data() throws -> Data {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in url.pathComponents.indices {
            let candidate = url.appendingPathComponent("fixtures/shop/catalogue.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            url = url.deletingLastPathComponent()
        }
        throw Fixture.NotFound(description: "No fixtures/shop/catalogue.json above \(#filePath)")
    }

    static func items() throws -> [ShopItem] {
        try JSONDecoder().decode(File.self, from: data()).items
    }
}

@Suite struct ShopCatalogueTests {
    @Test func theSwiftCopyMatchesTheFixture() throws {
        let fixture = try ShopCatalogueFixture.items()
        #expect(fixture == ShopCatalogue.items)
    }

    /// An item key added to the file needs a property here too, so an unknown key fails rather
    /// than being skipped by the decoder.
    @Test func everyItemHasExactlyTheKeysTheAppReads() throws {
        let object = try #require(JSONSerialization.jsonObject(with: ShopCatalogueFixture.data()) as? [String: Any])
        #expect(Set(object.keys) == ["items"])
        let items = try #require(object["items"] as? [[String: Any]])
        #expect(items.count == ShopCatalogue.items.count)
        for item in items {
            #expect(Set(item.keys) == ["id", "part", "option", "price", "plus"])
        }
    }

    @Test func theCatalogueIsWellFormed() {
        let items = ShopCatalogue.items
        #expect(Set(items.map(\.id)).count == items.count)
        for item in items {
            #expect(item.id == ShopItem.id(part: item.part, option: item.option))
            // Defaults aren't sold, Plus items aren't sold for coins.
            #expect(item.option >= 1)
            if item.plus {
                #expect(item.price == 0)
            } else {
                #expect(item.price > 0)
            }
        }
        for part in ShopPart.allCases {
            #expect(!ShopCatalogue.items(for: part).isEmpty)
        }
    }

    @Test func itemsDressAnAvatar() throws {
        let cap = try #require(ShopCatalogue.item(id: "hat.3"))
        #expect(cap.part == .hat)
        #expect(ShopCatalogue.item(part: .hat, option: 3) == cap)
        #expect(ShopCatalogue.item(part: .hat, option: 0) == nil)
        #expect(ShopCatalogue.item(id: "hat.99") == nil)

        let avatar = AvatarCode("b1.c2.e0.h0")
        let dressed = cap.applied(to: avatar)
        #expect(dressed == AvatarCode("b1.c2.e0.h3"))
        #expect(cap.isWorn(by: dressed))
        #expect(!cap.isWorn(by: avatar))
        #expect(ShopPart.colour.option(in: dressed) == 2)
    }

    @Test func theFreePartsAnAvatarWearsAreItsItems() {
        // Body 1 and colour 2 are for sale; eyes 3 is a Plus item; hat 0 is the default.
        #expect(ShopCatalogue.freeItemIDs(wornBy: AvatarCode("b1.c2.e3.h0")) == ["body.1", "colour.2"])
        #expect(ShopCatalogue.freeItemIDs(wornBy: .default).isEmpty)
        // A part this build's catalogue doesn't have isn't an item.
        #expect(ShopCatalogue.freeItemIDs(wornBy: AvatarCode("b9.c0.e0.h0")).isEmpty)
    }
}
