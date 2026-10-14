import API
import Core
import Foundation
import Model
import Testing
@testable import Social

@MainActor
@Suite struct SquadsStoreTests {
    private func signedIn(_ configure: (inout FakeAPI.Answers) -> Void = { _ in }) async -> (FakeAPI, AccountStore, SquadsStore, EventLog) {
        let api = FakeAPI(token: "t", configure)
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let squads = SquadsStore(api: api, account: account)
        let events = EventLog()
        squads.analytics = events.analytics
        return (api, account, squads, events)
    }

    @Test func refreshLoadsTheSquadsInTheServersOrder() async {
        let (api, _, squads, _) = await signedIn { $0.squads = [TestData.owls, TestData.goblins] }
        #expect(!squads.hasLoaded)
        await squads.refresh()
        #expect(squads.squads == [TestData.owls, TestData.goblins])
        #expect(squads.hasLoaded)
        #expect(!squads.isLoading)
        #expect(squads.problem == nil)
        #expect(squads.squad(id: TestData.goblins.id) == TestData.goblins)
        #expect(api.calls.last == .squads)
    }

    @Test func aFailedRefreshKeepsTheListAndSaysWhy() async {
        let (api, _, squads, _) = await signedIn { $0.squads = [TestData.goblins] }
        await squads.refresh()
        api.set { $0.failures["squads"] = .offline }
        await squads.refresh()
        #expect(squads.squads == [TestData.goblins])
        #expect(squads.problem == APIError.offline.errorDescription)

        api.set { $0.failures = [:] }
        await squads.refresh()
        #expect(squads.problem == nil)
    }

    @Test func nothingLoadsSignedOutOrBeforeTheHandleIsPicked() async throws {
        let signedOut = FakeAPI()
        let store = SquadsStore(api: signedOut, account: AccountStore(api: signedOut, cache: TestData.cache()))
        await store.refresh()
        #expect(signedOut.calls.isEmpty)

        let api = FakeAPI { $0.user = TestData.newcomer }
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)
        let squads = SquadsStore(api: api, account: account)
        await squads.refresh()
        #expect(!api.calls.contains(.squads))
        #expect(!squads.hasLoaded)
    }

    @Test func withoutTheAccountTheSessionIsEnough() async {
        let api = FakeAPI(token: "t") { $0.squads = [TestData.goblins] }
        let squads = SquadsStore(api: api)
        await squads.refresh()
        #expect(squads.squads == [TestData.goblins])

        let none = FakeAPI()
        let empty = SquadsStore(api: none)
        await empty.refresh()
        #expect(none.calls.isEmpty)
    }

    @Test func creatingTrimsTheNameAndAddsTheSquad() async throws {
        let (api, _, squads, events) = await signedIn { $0.squads = [TestData.owls] }
        await squads.refresh()
        let made = try await squads.create(name: "  Library Goblins ")
        #expect(api.calls.last == .createSquad("Library Goblins", tz: TimeZone.current.identifier))
        #expect(made.name == "Library Goblins")
        #expect(made.ownerId == TestData.ava.id)
        #expect(squads.squads.map(\.id) == [TestData.owls.id, made.id])
        #expect(events.count(.squadCreated) == 1)
    }

    @Test func badNamesFailWithoutAsking() async throws {
        let (api, _, squads, events) = await signedIn()
        let before = api.calls.count
        await #expect(throws: APIError.server(status: 422, code: .nameInvalid, message: nil)) {
            try await squads.create(name: "   ")
        }
        await #expect(throws: APIError.server(status: 422, code: .nameInvalid, message: nil)) {
            try await squads.create(name: String(repeating: "x", count: 21))
        }
        await #expect(throws: APIError.server(status: 422, code: .nameNotAllowed, message: nil)) {
            try await squads.create(name: "Lockin Official")
        }
        // Twenty is fine for a squad, though not for a person.
        _ = try await squads.create(name: String(repeating: "x", count: 20))
        #expect(api.calls.count == before + 1)
        #expect(events.count(.squadCreated) == 1)
    }

    @Test func aFreeLimitComesThroughWithItsLimit() async throws {
        let (api, _, squads, _) = await signedIn()
        api.set {
            $0.failures["createSquad"] = .server(status: 402, code: .plusRequired, message: nil, details: APIErrorDetails(limit: "squads"))
        }
        do {
            _ = try await squads.create(name: "Second")
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.plusLimit == "squads")
        }
        #expect(squads.squads.isEmpty)
    }

    @Test func renamingReplacesTheSquadWhereItIs() async throws {
        let (api, _, squads, _) = await signedIn { $0.squads = [TestData.owls, TestData.goblins] }
        await squads.refresh()
        let renamed = try await squads.rename(TestData.owls, to: " Early Birds ")
        #expect(api.calls.last == .renameSquad(TestData.owls.id, "Early Birds"))
        #expect(renamed.name == "Early Birds")
        #expect(squads.squads.map(\.name) == ["Early Birds", "Library Goblins"])

        api.set { $0.failures["renameSquad"] = .server(status: 403, code: .notOwner, message: nil) }
        await #expect(throws: APIError.server(status: 403, code: .notOwner, message: nil)) {
            try await squads.rename(TestData.goblins, to: "Mine")
        }
    }

    @Test func invitingGetsTheSquadsCode() async throws {
        let (api, _, squads, events) = await signedIn { $0.squads = [TestData.goblins] }
        let code = try await squads.invite(TestData.goblins)
        #expect(code == TestData.squadCode)
        #expect(api.calls.last == .squadInvite(TestData.goblins.id))
        squads.noteInviteShared()
        #expect(events.count(.inviteShared) == 1)
    }

    @Test func joiningNormalisesTheCodeAndAddsTheSquad() async throws {
        let (api, _, squads, events) = await signedIn { $0.squads = [TestData.owls] }
        await squads.refresh()
        let joined = try await squads.join(code: " sqd2-cdef ")
        #expect(joined == TestData.goblins)
        #expect(api.calls.last == .joinSquad("SQD2CDEF"))
        #expect(squads.squads.map(\.id) == [TestData.owls.id, TestData.goblins.id])
        #expect(events.count(.inviteRedeemed) == 1)
    }

    @Test func impossibleCodesFailWithoutAsking() async {
        let (api, _, squads, _) = await signedIn()
        let before = api.calls.count
        await #expect(throws: APIError.server(status: 404, code: .codeNotFound, message: nil)) {
            try await squads.join(code: "SQD2CDE0")
        }
        #expect(api.calls.count == before)
    }

    @Test func joinErrorsComeThroughWithTheirCodes() async {
        let (api, _, squads, _) = await signedIn()
        let cases: [APIError] = [
            .server(status: 409, code: .alreadyMember, message: nil),
            .server(status: 410, code: .codeExpired, message: nil),
            .server(status: 403, code: .blocked, message: nil),
            .server(status: 402, code: .plusRequired, message: nil, details: APIErrorDetails(limit: "members")),
        ]
        for failure in cases {
            api.set { $0.failures["joinSquad"] = failure }
            await #expect(throws: failure) {
                try await squads.join(code: "SQD2CDEF")
            }
        }
        #expect(squads.squads.isEmpty)
    }

    @Test func mutingMovesAtOnceAndBackIfItFails() async {
        let (api, _, squads, _) = await signedIn { $0.squads = [TestData.goblins] }
        await squads.refresh()
        await squads.setMuted(TestData.goblins, true)
        #expect(api.calls.last == .setSquadMuted(TestData.goblins.id, true))
        #expect(squads.squads.first?.muted == true)

        api.set { $0.failures["setSquadMuted"] = .offline }
        await squads.setMuted(TestData.goblins, false)
        #expect(squads.squads.first?.muted == true)
        #expect(squads.problem == APIError.offline.errorDescription)
    }

    @Test func leavingRemovesTheSquad() async throws {
        let (api, _, squads, _) = await signedIn { $0.squads = [TestData.owls, TestData.goblins] }
        await squads.refresh()
        try await squads.leave(TestData.owls)
        #expect(api.calls.last == .leaveSquad(TestData.owls.id))
        #expect(squads.squads == [TestData.goblins])

        api.set { $0.failures["leaveSquad"] = .offline }
        await #expect(throws: APIError.offline) {
            try await squads.leave(TestData.goblins)
        }
        #expect(squads.squads == [TestData.goblins])
    }

    @Test func signingOutEmptiesTheStore() async {
        let (_, account, squads, _) = await signedIn { $0.squads = [TestData.goblins] }
        await squads.refresh()
        account.signOut()
        #expect(squads.squads.isEmpty)
        #expect(!squads.hasLoaded)
        await account.signOutTask?.value
    }

    @Test func aRejectedSessionSignsOut() async {
        let (api, account, squads, _) = await signedIn { $0.squads = [TestData.goblins] }
        await squads.refresh()
        api.set { $0.failures["squads"] = .server(status: 401, code: .unauthorised, message: nil) }
        await squads.refresh()
        #expect(account.state == .signedOut)
        #expect(squads.squads.isEmpty)
        #expect(squads.problem == nil)
    }

    @Test func previewsHoldTheirSquadsAndNeverFail() async throws {
        let squads = SquadsStore.preview(squads: [PreviewAPI.sampleSquad, PreviewAPI.sampleLiveSquad])
        #expect(squads.squads.map(\.id) == [PreviewAPI.sampleSquad.id, PreviewAPI.sampleLiveSquad.id])
        #expect(squads.hasLoaded)
        await squads.refresh()
        #expect(squads.squads.count == 2)
        let made = try await squads.create(name: "Desk Crew")
        #expect(made.name == "Desk Crew")
        let joined = try await squads.join(code: "KQ7M2XPA")
        #expect(joined.id == PreviewAPI.sampleLiveSquad.id)
        _ = try await squads.invite(PreviewAPI.sampleSquad)
        await squads.setMuted(PreviewAPI.sampleSquad, true)
        #expect(squads.squad(id: PreviewAPI.sampleSquad.id)?.muted == true)
        #expect(PreviewAPI.sampleSquad.members.count == 4)
        #expect(PreviewAPI.sampleLiveSquad.isLive)
    }
}

@MainActor
@Suite struct RedeemInviteTests {
    private func stores(_ configure: (inout FakeAPI.Answers) -> Void = { _ in }) async -> (FakeAPI, SquadsStore, FriendsStore) {
        let api = FakeAPI(token: "t", configure)
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let friends = FriendsStore(api: api, account: account)
        await friends.refresh()
        return (api, SquadsStore(api: api, account: account), friends)
    }

    @Test func aSquadCodeJoinsTheSquad() async throws {
        let (api, squads, friends) = await stores()
        let target = try await redeemInvite(code: "sqd2 cdef", squads: squads, friends: friends)
        #expect(target == .squad(TestData.goblins))
        #expect(api.calls.last == .joinSquad("SQD2CDEF"))
        #expect(!api.calls.contains(.redeem("SQD2CDEF")))
        #expect(squads.squads == [TestData.goblins])
        #expect(friends.friends.isEmpty)
    }

    @Test func aFriendCodeFallsBackToTheFriends() async throws {
        let (api, squads, friends) = await stores {
            $0.failures["joinSquad"] = .server(status: 422, code: .friendCode, message: "That's a friend code.")
        }
        let target = try await redeemInvite(code: "KQ7M2XPA", squads: squads, friends: friends)
        #expect(target == .friend(TestData.noor))
        #expect(Array(api.calls.suffix(2)) == [.joinSquad("KQ7M2XPA"), .redeem("KQ7M2XPA")])
        #expect(friends.friends == [TestData.noor])
        #expect(squads.squads.isEmpty)
    }

    @Test func otherSquadErrorsDoNotFallBack() async throws {
        let (api, squads, friends) = await stores {
            $0.failures["joinSquad"] = .server(status: 410, code: .codeExpired, message: nil)
        }
        await #expect(throws: APIError.server(status: 410, code: .codeExpired, message: nil)) {
            try await redeemInvite(code: "KQ7M2XPA", squads: squads, friends: friends)
        }
        #expect(!api.calls.contains(.redeem("KQ7M2XPA")))
    }

    @Test func aFriendsOwnFailureComesThrough() async throws {
        let (_, squads, friends) = await stores {
            $0.failures["joinSquad"] = .server(status: 422, code: .friendCode, message: nil)
            $0.failures["redeem"] = .server(status: 409, code: .alreadyFriends, message: nil)
        }
        await #expect(throws: APIError.server(status: 409, code: .alreadyFriends, message: nil)) {
            try await redeemInvite(code: "KQ7M2XPA", squads: squads, friends: friends)
        }
    }

    @Test func impossibleCodesAndYourOwnFailWithoutAsking() async throws {
        let (api, squads, friends) = await stores()
        let before = api.calls.count
        await #expect(throws: APIError.server(status: 404, code: .codeNotFound, message: nil)) {
            try await redeemInvite(code: "nope", squads: squads, friends: friends)
        }
        await #expect(throws: APIError.server(status: 422, code: .ownCode, message: nil)) {
            try await redeemInvite(code: TestData.code.code, squads: squads, friends: friends)
        }
        #expect(api.calls.count == before)
    }

    @Test func aPendingInviteLinkIsRedeemedOnce() async throws {
        let (_, squads, friends) = await stores()
        #expect(try await friends.redeemPendingInvite(squads: squads) == nil)

        let link = try #require(InviteLink(url: URL(string: "https://lockin.example/j/SQD2CDEF")!))
        friends.openInvite(link)
        let target = try await friends.redeemPendingInvite(squads: squads)
        #expect(target == .squad(TestData.goblins))
        #expect(friends.pendingInviteCode == nil)
        #expect(try await friends.redeemPendingInvite(squads: squads) == nil)
    }
}
