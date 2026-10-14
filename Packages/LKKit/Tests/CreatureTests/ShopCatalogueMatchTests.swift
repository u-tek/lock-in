import Model
import Testing
@testable import Creature

/// The shop (`ShopCatalogue`, a copy of `fixtures/shop/catalogue.json`) sells what the Lockling can
/// draw (`CreatureCatalogue`), and both agree on what's Lockin Plus.
@Suite struct ShopCatalogueMatchTests {
    private func options(_ part: ShopPart) -> [CreatureOption] {
        switch part {
        case .body: CreatureCatalogue.bodies
        case .colour: CreatureCatalogue.colours
        case .eyes: CreatureCatalogue.eyes
        case .hat: CreatureCatalogue.hats
        }
    }

    @Test(arguments: ShopPart.allCases)
    func everyOptionButTheDefaultIsForSale(part: ShopPart) {
        let drawn = options(part).map(\.id).filter { $0 != 0 }
        let sold = ShopCatalogue.items(for: part).map(\.option)
        #expect(Set(drawn) == Set(sold))
    }

    @Test(arguments: ShopPart.allCases)
    func plusItemsArePlusOptions(part: ShopPart) {
        for item in ShopCatalogue.items(for: part) {
            let option = options(part).first { $0.id == item.option }
            #expect(option?.isPlus == item.plus, "\(item.id)")
        }
    }
}
