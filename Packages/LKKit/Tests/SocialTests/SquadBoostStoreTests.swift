import API
import Core
import Foundation
import Model
import Testing
@testable import Social

// Lockin Plus in the stores (docs/milestones/M7.md): Squad Boost's accessory picker, Demo Buddy's
// button, and the account after `POST /me/plus/refresh`.

@MainActor
@Suite struct SquadBoostStoreTests {
    private static var boosted: Squad {
        var squad = TestData.goblins
        squad.boosted = true
        return squad
    }

    private static var review: Squad {
        var squad = TestData.owls
        squad.id = "SqReview01"
        squad.name = "Review Squad"
        squad.openSessionId = nil
        squad.members.append(SquadMember(
            id: "DemoBuddy0",
            handle: "demobuddy",
            displayName: "Demo Buddy",
            avatarCode: "b2.c5.e4.h3",
            joinedAt: 1_791_900_060,
            isBot: true
        ))
        return squad
    }

    private func signedIn(_ squads: [Squad]) async -> (FakeAPI, AccountStore, SquadsStore) {
        let api = FakeAPI(token: "t") { $0.squads = squads }
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let store = SquadsStore(api: api, account: account)
        await store.refresh()
        return (api, account, store)
    }

    @Test func aBoostedSquadsPetDressesForEveryone() async throws {
        let (api, _, squads) = await signedIn([Self.boosted])
        let saved = try await squads.setPetAccessory(Self.boosted, to: PetAccessory.bow.rawValue)
        #expect(api.calls.last == .setPetAccessory(Self.boosted.id, 5))
        #expect(saved.pet.accessory == 5)
        #expect(squads.squad(id: Self.boosted.id)?.pet.wornAccessory == .bow)

        try await squads.setPetAccessory(Self.boosted, to: nil)
        #expect(api.calls.last == .setPetAccessory(Self.boosted.id, nil))
        #expect(squads.squad(id: Self.boosted.id)?.pet.accessory == nil)
    }

    /// Without the boost the server says 402 `plus_required` "boost": the pet changes back and the
    /// error goes on, for the paywall.
    @Test func withoutTheBoostItsThePaywall() async throws {
        let (_, _, squads) = await signedIn([TestData.goblins])
        do {
            try await squads.setPetAccessory(TestData.goblins, to: PetAccessory.scarf.rawValue)
            Issue.record("Expected plus_required")
        } catch let error as APIError {
            #expect(error.code == .plusRequired)
            #expect(error.plusLimit == "boost")
        }
        #expect(squads.squad(id: TestData.goblins.id)?.pet.accessory == nil)
    }

    @Test func askingDemoBuddyOpensTheRoom() async throws {
        let (api, _, squads) = await signedIn([Self.review, TestData.goblins])
        #expect(squads.squad(id: Self.review.id)?.hasBot == true)
        #expect(squads.squad(id: TestData.goblins.id)?.hasBot == false)

        let session = try await squads.askDemoBuddy(Self.review)
        #expect(api.calls.last == .askDemoBuddy(Self.review.id))
        #expect(session.squadId == Self.review.id)
        #expect(squads.squad(id: Self.review.id)?.openSessionId == session.id)
        #expect(squads.squad(id: Self.review.id)?.isLive == true)

        // A squad without Demo Buddy: 404, nothing changes.
        await #expect(throws: APIError.self) {
            try await squads.askDemoBuddy(TestData.goblins)
        }
        #expect(squads.squad(id: TestData.goblins.id)?.isLive == false)
    }
}

@MainActor
@Suite struct PlusRefreshTests {
    @Test func theRefreshedAccountIsTaken() async {
        let api = FakeAPI(token: "t") { $0.refreshedPlusUntil = 1_900_000_000 }
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        #expect(account.user?.plusUntil == nil)

        #expect(await account.refreshPlus())
        #expect(api.calls.last == .refreshPlus)
        #expect(account.user?.plusUntil == 1_900_000_000)
        #expect(account.user?.hasPlus(at: Date(timeIntervalSince1970: 1_800_000_000)) == true)
    }

    @Test func signedOutOrOfflineItWaits() async {
        let signedOut = FakeAPI()
        let nobody = AccountStore(api: signedOut, cache: TestData.cache())
        #expect(await nobody.refreshPlus() == false)
        #expect(signedOut.calls.isEmpty)

        let api = FakeAPI(token: "t") { $0.failures["refreshPlus"] = .server(status: 503, code: .tryAgain, message: nil) }
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let before = account.user
        #expect(await account.refreshPlus() == false)
        #expect(account.user == before)
        #expect(account.state.isSignedIn)
    }
}
