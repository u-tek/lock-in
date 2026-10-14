import Foundation
import Testing
@testable import Model

// Squad Boost's accessories (docs/milestones/M7.md): the pet code's `.a<n>`, and the catalogue's
// part `pet`.

@Suite struct PetCodeAccessoryTests {
    @Test func readsTheAccessoryAfterTheStage() {
        let pet = PetCode("sprout.2.a3")
        #expect(pet.species == "sprout")
        #expect(pet.stage == 2)
        #expect(pet.accessory == 3)
        #expect(pet.wornAccessory == .flowerCrown)
        #expect(pet.code == "sprout.2.a3")
        #expect(pet.description == "sprout.2.a3")
        #expect(pet == PetCode(species: "sprout", stage: 2, accessory: 3))
        #expect(pet != PetCode(species: "sprout", stage: 2))
    }

    @Test func withoutOneThereIsNone() {
        #expect(PetCode("sprout.2").accessory == nil)
        #expect(PetCode("sprout.2").wornAccessory == nil)
        #expect(PetCode("sprout.2").code == "sprout.2")
        #expect(PetCode(species: "sprout", stage: 2).accessory == nil)
    }

    @Test(arguments: [
        ("sprout.2.a1", 1), ("sprout.2.a6", 6), ("sprout.2.A4", 4), ("sprout.2. a5 ", 5), ("sprout.2.a07", 7),
        ("sprout.2.a99", 99), ("puff.0.a2", 2), ("ember.4.a2.extra", 2),
    ])
    func readsEveryWellFormedAccessory(code: String, accessory: Int) {
        #expect(PetCode(code).accessory == accessory)
    }

    @Test(arguments: [
        "sprout.2.a0", "sprout.2.a100", "sprout.2.a", "sprout.2.3", "sprout.2.hat", "sprout.2.a-1", "sprout.2.a+2",
        "sprout.2.a99999999999999999999", "sprout.2.extra", "sprout.2..a3", "sprout.a3",
    ])
    func garbledAccessoriesAreNone(code: String) {
        let pet = PetCode(code)
        #expect(pet.accessory == nil, "\(code)")
        #expect(PetCode(pet.code) == pet)
    }

    /// One this version can't draw yet is kept, so the code reads back the same, but isn't worn.
    @Test func anUnknownAccessoryIsKeptButNotWorn() {
        let pet = PetCode("pebble.3.a42")
        #expect(pet.accessory == 42)
        #expect(pet.wornAccessory == nil)
        #expect(PetCode(pet.code) == pet)
    }

    @Test func outOfRangeAccessoriesAreDropped() {
        #expect(PetCode(species: "puff", stage: 1, accessory: 0).accessory == nil)
        #expect(PetCode(species: "puff", stage: 1, accessory: -2).accessory == nil)
        #expect(PetCode(species: "puff", stage: 1, accessory: 100).accessory == nil)
        #expect(PetCode(species: "puff", stage: 1, accessory: 99).accessory == 99)
    }

    /// The longest code the server allows still fits the Live Activity's species and stage rules.
    @Test func everyAccessoryRoundTrips() {
        for accessory in PetAccessory.allCases {
            for stage in 0...5 {
                let pet = PetCode(species: "sprout", stage: stage, accessory: accessory.rawValue)
                #expect(PetCode(pet.code) == pet)
                #expect(pet.wornAccessory == accessory)
            }
        }
    }
}

@Suite struct PetAccessoryTests {
    @Test func theAccessoriesAreTheCataloguesPetItems() throws {
        let object = try #require(JSONSerialization.jsonObject(with: ShopCatalogueFixture.data()) as? [String: Any])
        let items = try #require(object["items"] as? [[String: Any]])
        let pets = items.filter { ($0["part"] as? String) == PetAccessory.shopPart }
        #expect(pets.compactMap { $0["id"] as? String } == PetAccessory.allCases.map(\.shopItemID))
        #expect(pets.compactMap { $0["option"] as? Int } == PetAccessory.allCases.map(\.rawValue))
        // Plus items, never sold for coins.
        for item in pets {
            #expect(item["plus"] as? Bool == true)
            #expect(item["price"] as? Int == 0)
        }
    }

    @Test func numbersAndTitles() {
        #expect(PetAccessory.allCases.map(\.rawValue) == [1, 2, 3, 4, 5, 6])
        #expect(PetAccessory.allCases.map(\.title) == ["Scarf", "Party hat", "Flower crown", "Glasses", "Bow", "Star clip"])
        #expect(PetAccessory.partyHat.shopItemID == "pet.2")
        #expect(PetAccessory.allCases.allSatisfy { PetCode.accessoryRange.contains($0.rawValue) })
    }
}
