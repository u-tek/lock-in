import Creature
import Foundation
import Model
import StoreKit
import Testing
@testable import Paywall

// No StoreKit configuration runs with the tests, so nothing here may reach the App Store: these
// cover the preview store, the fallbacks before products load, and the rules on their own.

@MainActor
@Suite struct PlusStoreTests {
    @Test func previewNeverCallsStoreKit() async throws {
        let store = PlusStore.preview()
        #expect(store.isPreview)
        #expect(!store.isPlus)

        await store.load()
        #expect(store.updatesTask == nil)
        #expect(store.products.isEmpty)
        #expect(try await store.purchase(.yearly) == false)
        await store.restore()
        #expect(!store.isPlus)

        let plus = PlusStore.preview(isPlus: true)
        await plus.load()
        await plus.restore()
        #expect(plus.isPlus)
        #expect(plus.updatesTask == nil)
    }

    @Test func pricesFallBackUntilTheProductsLoad() {
        let store = PlusStore(bundleID: "app.lockin")
        for plan in PlusPlan.allCases {
            #expect(store.displayPrice(for: plan) == plan.fallbackPrice)
        }
        #expect(store.monthlyEquivalentOfYearly() == "A$2.08")
        #expect(store.isTrialAvailable)
        #expect(!store.isPlus)
        // Making a store starts nothing; `load()` does.
        #expect(store.updatesTask == nil)
        #expect(store.productIDs == ["app.lockin.plus.yearly", "app.lockin.plus.monthly", "app.lockin.plus.lifetime"])
    }

    @Test func buyingBeforeTheProductsLoadFailsPolitely() async {
        let store = PlusStore(bundleID: "app.lockin")
        await #expect(throws: PlusStoreError.unavailable) {
            try await store.purchase(.monthly)
        }
        #expect(PlusStoreError.unavailable.errorDescription?.hasPrefix("Purchases aren't available yet") == true)
    }

    @Test func paywallBuildsWithAPreviewStore() {
        _ = PaywallView(store: .preview(), avatar: .default) {}
        _ = PaywallView(store: .preview(isPlus: true), avatar: AvatarCode("b1.c2.e3.h0")) {}
    }

    @Test func theHeroWearsTheCrown() throws {
        let crown = try #require(PaywallView.crownHatID(in: CreatureCatalogue.hats))
        let option = try #require(CreatureCatalogue.hats.first { $0.id == crown })
        #expect(option.isPlus)
        #expect(option.name == "Crown")

        let crowned = PaywallView.crowned(AvatarCode("b2.c3.e1.h0"))
        #expect(crowned == AvatarCode(body: 2, colour: 3, eyes: 1, hat: crown))
    }

    @Test func withoutACrownAnyPlusHatWillDo() {
        let free = CreatureOption(id: 0, name: "None")
        let halo = CreatureOption(id: 7, name: "Halo", isPlus: true)
        #expect(PaywallView.crownHatID(in: [free, halo]) == 7)
        #expect(PaywallView.crownHatID(in: [free]) == nil)
        #expect(PaywallView.crownHatID(in: []) == nil)
    }
}

@Suite struct EntitlementTests {
    private let ids: Set<String> = ["app.lockin.plus.yearly", "app.lockin.plus.monthly", "app.lockin.plus.lifetime"]
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func grants(_ productID: String, revoked: Date? = nil, expires: Date? = nil) -> Bool {
        PlusStore.grantsPlus(productID: productID, revocationDate: revoked, expirationDate: expires, productIDs: ids, now: now)
    }

    @Test func lifetimeAndLiveSubscriptionsGrantPlus() {
        #expect(grants("app.lockin.plus.lifetime"))
        #expect(grants("app.lockin.plus.yearly", expires: now.addingTimeInterval(86_400)))
    }

    @Test func expiredRevokedAndOtherProductsDont() {
        #expect(!grants("app.lockin.plus.monthly", expires: now))
        #expect(!grants("app.lockin.plus.monthly", expires: now.addingTimeInterval(-1)))
        #expect(!grants("app.lockin.plus.lifetime", revoked: now.addingTimeInterval(-60)))
        #expect(!grants("app.lockin.coins.small"))
    }
}

@Suite struct PlusStoreErrorTests {
    @Test func storeKitErrorsBecomeFriendlyOnes() {
        #expect(PlusStoreError(StoreKitError.userCancelled) == nil)
        #expect(PlusStoreError(StoreKitError.networkError(URLError(.notConnectedToInternet))) == .network)
        #expect(PlusStoreError(StoreKitError.notAvailableInStorefront) == .unavailable)
        #expect(PlusStoreError(StoreKitError.unknown) == .failed)
        #expect(PlusStoreError(Product.PurchaseError.productUnavailable) == .unavailable)
        #expect(PlusStoreError(Product.PurchaseError.purchaseNotAllowed) == .notAllowed)
        #expect(PlusStoreError(Product.PurchaseError.invalidQuantity) == .failed)
        #expect(PlusStoreError(PlusStoreError.unverified) == .unverified)
        #expect(PlusStoreError(CocoaError(.fileNoSuchFile)) == .failed)
    }

    @Test func everyErrorHasAMessage() {
        let all: [PlusStoreError] = [.unavailable, .notAllowed, .network, .unverified, .failed]
        for error in all {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
