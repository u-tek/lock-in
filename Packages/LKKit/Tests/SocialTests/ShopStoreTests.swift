import API
import Core
import Foundation
import Model
import Testing
@testable import Social

@MainActor
@Suite struct ShopStoreTests {
    private let cap = ShopCatalogue.item(id: "hat.3")!         // 100 coins
    private let blue = ShopCatalogue.item(id: "colour.1")!     // 40 coins
    private let crown = ShopCatalogue.item(id: "hat.5")!       // Plus

    /// Signed out, with `earned` coins counted on this phone.
    private func signedOut(earned: Int, wallet: LocalWallet = .inMemory(LocalWallet.Contents())) -> (FakeAPI, AccountStore, ShopStore) {
        let api = FakeAPI()
        let account = AccountStore(api: api, cache: TestData.cache())
        let shop = ShopStore(api: api, account: account, wallet: wallet, localEarned: earned)
        return (api, account, shop)
    }

    /// Signed in as Ava, whose account has `coins`.
    private func signedIn(
        coins: Int,
        wallet: LocalWallet = .inMemory(LocalWallet.Contents()),
        earned: Int = 0,
        _ configure: (inout FakeAPI.Answers) -> Void = { _ in }
    ) async -> (FakeAPI, AccountStore, ShopStore) {
        let api = FakeAPI(token: "t") { answers in
            answers.user.coins = coins
            configure(&answers)
        }
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let shop = ShopStore(api: api, account: account, wallet: wallet, localEarned: earned)
        return (api, account, shop)
    }

    // MARK: - Signed out

    @Test func signedOutTheBalanceIsThisPhonesLessWhatTheShopTook() {
        let (_, _, shop) = signedOut(earned: 150, wallet: .inMemory(LocalWallet.Contents(spent: 40, owned: ["colour.1"])))
        #expect(!shop.isSignedIn)
        #expect(shop.coins == 110)
        #expect(shop.owns(blue))
        #expect(!shop.owns(cap))
        #expect(shop.shortfall(for: cap) == 0)
        shop.localEarned = 60
        #expect(shop.coins == 20)
        #expect(shop.shortfall(for: cap) == 80)
    }

    @Test func defaultsAreAlwaysYours() {
        let (_, _, shop) = signedOut(earned: 0)
        for part in ShopPart.allCases {
            #expect(shop.owns(part: part, option: 0))
        }
        #expect(!shop.owns(part: .hat, option: 3))
    }

    @Test func buyingSignedOutSpendsThisPhonesCoinsAndKeepsTheItem() async throws {
        let wallet = LocalWallet.inMemory(LocalWallet.Contents())
        let (api, _, shop) = signedOut(earned: 130, wallet: wallet)
        try await shop.buy(cap)
        #expect(shop.coins == 30)
        #expect(shop.owns(cap))
        #expect(wallet.load() == LocalWallet.Contents(spent: 100, owned: ["hat.3"]))
        // Nothing asked of the server.
        #expect(api.calls.isEmpty)

        // Buying it again does nothing.
        try await shop.buy(cap)
        #expect(shop.coins == 30)

        // A shop opened later on the same phone remembers.
        let reopened = ShopStore(api: api, account: AccountStore(api: api, cache: TestData.cache()), wallet: wallet, localEarned: 130)
        #expect(reopened.coins == 30)
        #expect(reopened.owns(cap))
    }

    @Test func notEnoughCoinsSignedOutBuysNothing() async {
        let (_, _, shop) = signedOut(earned: 99)
        await #expect(throws: APIError.server(status: 402, code: .notEnoughCoins, message: nil)) {
            try await shop.buy(cap)
        }
        #expect(shop.coins == 99)
        #expect(!shop.owns(cap))
        #expect(shop.shortfall(for: cap) == 1)
    }

    @Test func plusItemsAreNeverSoldForCoins() async {
        let (_, _, shop) = signedOut(earned: 1_000)
        await #expect(throws: APIError.server(status: 402, code: .plusRequired, message: nil)) {
            try await shop.buy(crown)
        }
        #expect(shop.coins == 1_000)
    }

    @Test func theFirstShopKeepsTheFreePartsYoureWearing() {
        let wallet = LocalWallet.inMemory()
        // Colour 2 and hat 3 are for sale, eyes 3 is Plus.
        let api = FakeAPI()
        let shop = ShopStore(api: api, account: AccountStore(api: api, cache: TestData.cache()), wallet: wallet, wearing: AvatarCode("b0.c2.e3.h3"))
        #expect(shop.owned == ["colour.2", "hat.3"])
        #expect(wallet.load()?.owned == ["colour.2", "hat.3"])

        // Only the first time: a saved wallet stands.
        let later = ShopStore(api: api, account: AccountStore(api: api, cache: TestData.cache()), wallet: wallet, wearing: AvatarCode("b1.c1.e1.h1"))
        #expect(later.owned == ["colour.2", "hat.3"])
    }

    @Test func theOnboardingLocklingsPartsAreKept() {
        let (_, _, shop) = signedOut(earned: 0)
        shop.keepParts(of: AvatarCode("b2.c0.e3.h1"))
        #expect(shop.owned == ["body.2", "hat.1"])
        shop.keepParts(of: AvatarCode("b2.c0.e0.h0"))
        #expect(shop.wallet.owned == ["body.2", "hat.1"])
    }

    // MARK: - Signed in

    @Test func signedInTheBalanceAndItemsAreTheServers() async {
        let (api, _, shop) = await signedIn(coins: 420, wallet: .inMemory(LocalWallet.Contents(owned: ["colour.1"], imported: [TestData.ava.id]))) {
            $0.owned = ["hat.1"]
        }
        #expect(shop.isSignedIn)
        #expect(shop.coins == 420)
        // Until the server has said, this phone's list stands in.
        #expect(shop.owned == ["colour.1"])
        await shop.refresh()
        #expect(shop.owned == ["hat.1"])
        #expect(api.calls.suffix(2) == [.me, .cosmetics])
    }

    @Test func buyingSignedInGoesThroughTheServer() async throws {
        let (api, account, shop) = await signedIn(coins: 130, wallet: .inMemory(LocalWallet.Contents(imported: [TestData.ava.id])))
        try await shop.buy(cap)
        #expect(api.calls.last == .buy("hat.3"))
        #expect(shop.coins == 30)
        #expect(account.user?.coins == 30)
        #expect(shop.owns(cap))
        #expect(shop.buying == nil)
        // This phone's wallet is left alone.
        #expect(shop.wallet.spent == 0)
    }

    @Test func theServersRefusalsComeThrough() async {
        let (_, _, shop) = await signedIn(coins: 50, wallet: .inMemory(LocalWallet.Contents(imported: [TestData.ava.id])))
        await #expect(throws: APIError.server(status: 402, code: .notEnoughCoins, message: nil)) {
            try await shop.buy(cap)
        }
        await #expect(throws: APIError.server(status: 402, code: .plusRequired, message: nil)) {
            try await shop.buy(crown)
        }
        #expect(shop.coins == 50)
        #expect(!shop.owns(cap))
    }

    @Test func alreadyOwnedCatchesUpWithWhatsOwned() async throws {
        let (api, _, shop) = await signedIn(coins: 500, wallet: .inMemory(LocalWallet.Contents(imported: [TestData.ava.id]))) {
            // Bought on another phone.
            $0.owned = ["hat.3"]
        }
        try await shop.buy(cap)
        #expect(api.calls.suffix(2) == [.buy("hat.3"), .cosmetics])
        #expect(shop.owns(cap))
        #expect(shop.coins == 500)
    }

    @Test func theFirstSignInBringsThisPhonesCoinsAndItemsOver() async {
        let wallet = LocalWallet.inMemory(LocalWallet.Contents(spent: 40, owned: ["colour.1", "hat.5"]))
        let (api, account, shop) = await signedIn(coins: 15, wallet: wallet, earned: 140)
        await shop.importIfNeeded()
        // 140 counted, 40 spent; the Plus item isn't sent.
        #expect(api.calls.last == .importCoins(coins: 100, owned: ["colour.1"]))
        #expect(shop.coins == 115)
        #expect(account.user?.coins == 115)
        #expect(shop.owned == ["colour.1"])
        #expect(wallet.load()?.imported == [TestData.ava.id])

        // Once per account.
        let before = api.calls.count
        await shop.importIfNeeded()
        await shop.refresh()
        #expect(!api.calls.dropFirst(before).contains { if case .importCoins = $0 { true } else { false } })
    }

    @Test func alreadyImportedCountsAsDone() async {
        let wallet = LocalWallet.inMemory(LocalWallet.Contents())
        let (api, _, shop) = await signedIn(coins: 15, wallet: wallet, earned: 80) { $0.imported = true }
        await shop.importIfNeeded()
        #expect(api.calls.last == .importCoins(coins: 80, owned: []))
        #expect(wallet.load()?.imported == [TestData.ava.id])
        #expect(shop.coins == 15)

        let before = api.calls.count
        await shop.importIfNeeded()
        #expect(api.calls.count == before)
    }

    @Test func anImportThatFailsIsTriedAgain() async {
        let (api, _, shop) = await signedIn(coins: 0, earned: 10) { $0.failures["importCoins"] = .offline }
        await shop.importIfNeeded()
        #expect(shop.wallet.imported.isEmpty)
        api.set { $0.failures = [:] }
        await shop.importIfNeeded()
        #expect(shop.wallet.imported == [TestData.ava.id])
        #expect(shop.coins == 10)
    }

    @Test func refreshImportsFirst() async {
        let (api, _, shop) = await signedIn(coins: 5, earned: 20)
        let before = api.calls.count
        await shop.refresh()
        #expect(Array(api.calls.dropFirst(before)) == [.importCoins(coins: 20, owned: []), .me, .cosmetics])
        #expect(shop.coins == 25)
    }

    @Test func signingOutGoesBackToThisPhonesCoins() async throws {
        let (_, account, shop) = await signedIn(coins: 300, wallet: .inMemory(LocalWallet.Contents(imported: [TestData.ava.id])), earned: 45) {
            $0.owned = ["hat.3"]
        }
        await shop.refresh()
        #expect(shop.coins == 300)
        #expect(shop.owns(cap))
        account.signOut()
        #expect(!shop.isSignedIn)
        #expect(shop.coins == 45)
        #expect(!shop.owns(cap))
        #expect(shop.serverOwned == nil)
    }

    @Test func nothingIsAskedSignedOut() async {
        let (api, _, shop) = signedOut(earned: 10)
        await shop.refresh()
        await shop.importIfNeeded()
        #expect(api.calls.isEmpty)
    }

    @Test func aPreviewShopNeverFails() async throws {
        let shop = ShopStore.preview(account: .preview(.signedOut), coins: 120, owned: ["colour.2"])
        #expect(shop.coins == 120)
        #expect(shop.owned == ["colour.2"])
        try await shop.buy(blue)
        #expect(shop.coins == 80)

        let signedIn = ShopStore.preview(account: .preview(.signedIn(PreviewAPI.sampleUser)), coins: 0, owned: ["hat.1"])
        #expect(signedIn.coins == PreviewAPI.sampleUser.coins)
        #expect(signedIn.owned == ["hat.1"])
    }
}

@Suite struct LocalWalletTests {
    @Test func aFileWalletRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lockin-wallet-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("wallet.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let wallet = LocalWallet.file(at: url)
        #expect(wallet.load() == nil)
        let contents = LocalWallet.Contents(spent: 140, owned: ["hat.3", "colour.1"], imported: ["uAva000001"])
        wallet.save(contents)
        #expect(LocalWallet.file(at: url).load() == contents)
    }

    @Test func missingKeysReadAsDefaults() throws {
        let contents = try JSONDecoder().decode(LocalWallet.Contents.self, from: Data(#"{"spent":12}"#.utf8))
        #expect(contents == LocalWallet.Contents(spent: 12))
    }
}
