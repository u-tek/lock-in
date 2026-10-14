import API
import Core
import Foundation
import Model
import Testing
@testable import Social

@MainActor
@Suite struct AccountStoreTests {
    @Test func withoutASessionItStartsSignedOut() async {
        let api = FakeAPI()
        let account = AccountStore(api: api, cache: TestData.cache())
        #expect(account.state == .signedOut)
        #expect(account.isConfigured)
        await account.restore()
        #expect(account.state == .signedOut)
        #expect(api.calls.isEmpty)
    }

    @Test func withoutAServerThereIsNothingToSignInto() async {
        let api = FakeAPI(isConfigured: false, token: "t")
        let account = AccountStore(api: api, cache: TestData.cache())
        #expect(!account.isConfigured)
        #expect(account.state == .signedOut)
        await account.restore()
        #expect(api.calls.isEmpty)
    }

    @Test func signingInWithoutAHandleAsksForOne() async throws {
        let api = FakeAPI { $0.user = TestData.newcomer; $0.isNew = true }
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: "c", displayName: "  Ava ")
        #expect(account.state == .needsHandle(TestData.newcomer))
        #expect(account.suggestedName == "Ava")
        #expect(api.calls == [.signIn(identityToken: "eyJ", displayName: "Ava")])
        #expect(api.hasSession)
    }

    @Test func aNameThatWouldNotPassIsNotSent() async throws {
        let api = FakeAPI { $0.user = TestData.newcomer }
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: "Christopher-Alexander")
        #expect(api.calls == [.signIn(identityToken: "eyJ", displayName: nil)])
        #expect(account.suggestedName == nil)
    }

    @Test func signingInWithAHandleGoesStraightIn() async throws {
        let api = FakeAPI()
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)
        #expect(account.state == .signedIn(TestData.ava))
    }

    @Test func pickingAHandleFinishesSigningIn() async throws {
        let api = FakeAPI { $0.user = TestData.newcomer }
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)

        try await account.setProfile(handle: "Noor_K", displayName: " Noor ", avatar: AvatarCode("b2.c4.e2.h0"))
        #expect(api.calls.last == .updateMe(ProfileUpdate(handle: "noor_k", displayName: "Noor", avatarCode: "b2.c4.e2.h0")))
        guard case .signedIn(let user) = account.state else {
            Issue.record("Expected to be signed in, not \(account.state)")
            return
        }
        #expect(user.handle == "noor_k")
        #expect(user.displayName == "Noor")
    }

    @Test func onlyWhatChangedIsSent() async throws {
        let api = FakeAPI(token: "t")
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        try await account.setProfile(handle: "ava", displayName: "Ava B", avatar: TestData.ava.avatar)
        #expect(api.calls.last == .updateMe(ProfileUpdate(displayName: "Ava B")))

        let before = api.calls.count
        try await account.setProfile(handle: "ava", displayName: "Ava B")
        #expect(api.calls.count == before)
    }

    @Test func aTakenHandleIsAnErrorAndChangesNothing() async throws {
        let api = FakeAPI { $0.user = TestData.newcomer }
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)
        api.set { $0.failures["updateMe"] = .server(status: 409, code: .handleTaken, message: nil) }

        await #expect(throws: APIError.server(status: 409, code: .handleTaken, message: nil)) {
            try await account.setProfile(handle: "ava", displayName: "Ava")
        }
        #expect(account.state == .needsHandle(TestData.newcomer))
    }

    @Test func handlesAreCheckedHereBeforeTheServerIsAsked() async {
        let api = FakeAPI(token: "t")
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let afterRestore = api.calls.count

        #expect(await account.checkHandle("") == .empty)
        #expect(await account.checkHandle("ab") == .invalid)
        #expect(await account.checkHandle("1ava") == .invalid)
        #expect(await account.checkHandle("admin") == .notAllowed)
        #expect(await account.checkHandle("Ava") == .yours)
        #expect(api.calls.count == afterRestore)

        #expect(await account.checkHandle("Noor.K") == .available)
        #expect(api.calls.last == .handle("noor.k"))

        api.set { $0.availability = HandleAvailability(available: false, reason: .taken) }
        #expect(await account.checkHandle("kai") == .taken)
        api.set { $0.availability = HandleAvailability(available: false, reason: .notAllowed) }
        #expect(await account.checkHandle("kai") == .notAllowed)
        api.set { $0.availability = HandleAvailability(available: false) }
        #expect(await account.checkHandle("kai") == .taken)

        // Offline, it doesn't stand in the way: saving asks again.
        api.set { $0.failures["handle"] = .offline }
        let offline = await account.checkHandle("kai")
        #expect(offline == .unverified)
        #expect(offline.canSave)
        #expect(!HandleStatus.checking.canSave)
        #expect(!HandleStatus.taken.canSave)
    }

    @Test func aCachedAccountOpensSignedInAndRestoreRefreshesIt() async {
        let cache = TestData.cache()
        let first = AccountStore(api: FakeAPI(token: "t"), cache: cache)
        await first.restore()
        #expect(first.state == .signedIn(TestData.ava))

        // Next launch, offline: the cached account shows, and stays.
        let offline = FakeAPI(token: "t") { $0.failures["me"] = .offline }
        let second = AccountStore(api: offline, cache: cache)
        #expect(second.state == .signedIn(TestData.ava))
        #expect(!second.isRestoring)
        await second.restore()
        #expect(second.state == .signedIn(TestData.ava))

        // The server has news.
        var renamed = TestData.ava
        renamed.displayName = "Ava B"
        let third = AccountStore(api: FakeAPI(token: "t") { $0.user = renamed }, cache: cache)
        await third.restore()
        #expect(third.state == .signedIn(renamed))
    }

    @Test func aRejectedSessionSignsOutAndForgetsTheCache() async {
        let cache = TestData.cache()
        let first = AccountStore(api: FakeAPI(token: "t"), cache: cache)
        await first.restore()

        let api = FakeAPI(token: "expired") { $0.failures["me"] = .server(status: 401, code: .unauthorised, message: nil) }
        let account = AccountStore(api: api, cache: cache)
        #expect(account.state == .signedIn(TestData.ava))
        await account.restore()
        #expect(account.state == .signedOut)
        #expect(!api.hasSession)
        #expect(AccountStore(api: FakeAPI(token: "t"), cache: cache).state == .signedOut)
    }

    @Test func aCacheWithoutATokenIsIgnored() async {
        let cache = TestData.cache()
        let first = AccountStore(api: FakeAPI(token: "t"), cache: cache)
        await first.restore()
        #expect(AccountStore(api: FakeAPI(token: nil), cache: cache).state == .signedOut)
    }

    @Test func signingOutForgetsTheSessionAndTheFriends() async throws {
        let api = FakeAPI(token: "t") { $0.friends = [TestData.noor] }
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let friends = FriendsStore(api: api, account: account)
        await friends.refresh()
        #expect(friends.friends == [TestData.noor])
        #expect(friends.code == TestData.code)

        account.signOut()
        #expect(account.state == .signedOut)
        #expect(!api.hasSession)
        #expect(friends.friends.isEmpty)
        #expect(friends.code == nil)
        #expect(!friends.hasLoaded)
    }

    @Test func deletingTheAccountSignsOut() async throws {
        let api = FakeAPI(token: "t")
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        try await account.deleteAccount()
        #expect(api.calls.last == .deleteMe)
        #expect(account.state == .signedOut)
        #expect(!api.hasSession)
    }

    @Test func aFailedDeletionKeepsTheAccount() async throws {
        let api = FakeAPI(token: "t") { $0.failures["deleteMe"] = .offline }
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        await #expect(throws: APIError.offline) {
            try await account.deleteAccount()
        }
        #expect(account.state == .signedIn(TestData.ava))
        #expect(api.hasSession)
    }

    @Test func theAvatarIsSavedOnlyWhenItChanged() async {
        let api = FakeAPI(token: "t")
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        await account.updateAvatar(TestData.ava.avatar)
        #expect(api.calls == [.me])

        await account.updateAvatar(AvatarCode("b3.c3.e3.h3"))
        #expect(api.calls.last == .updateMe(ProfileUpdate(avatarCode: "b3.c3.e3.h3")))
        #expect(account.user?.avatarCode == "b3.c3.e3.h3")

        // Signed out, there's nowhere to save it.
        account.signOut()
        let before = api.calls.count
        await account.updateAvatar(AvatarCode("b4.c4.e4.h4"))
        #expect(api.calls.count == before)
    }

    @Test func theDeviceWaitsForASessionAndIsSentOnce() async throws {
        let api = FakeAPI()
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.registerDevice(TestData.device)
        #expect(api.calls.isEmpty)

        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)
        #expect(api.calls.last == .registerDevice(TestData.device))

        await account.registerDevice(TestData.device)
        #expect(api.calls.filter { if case .registerDevice = $0 { true } else { false } }.count == 1)

        var changed = TestData.device
        changed.laEnabled = false
        await account.registerDevice(changed)
        #expect(api.calls.last == .registerDevice(changed))

        // A new account registers the phone again.
        account.signOut()
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)
        #expect(api.calls.last == .registerDevice(changed))
    }

    @Test func theConvenienceRegistrationFillsInTheBody() async throws {
        let api = FakeAPI(token: "t")
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        await account.registerDevice(token: "ff00", env: .production, laEnabled: true, frequentPushes: true, timeZone: "Europe/London", pushToStartToken: "ab")
        #expect(api.calls.last == .registerDevice(DeviceRegistration(
            apnsToken: "ff00",
            env: .production,
            pushToStartToken: "ab",
            laEnabled: true,
            frequentPushes: true,
            tz: "Europe/London"
        )))
    }

    @Test func previewsShowEveryStateWithoutANetwork() async {
        let signedOut = AccountStore.preview(.signedOut)
        #expect(signedOut.state == .signedOut)
        #expect(signedOut.isConfigured)
        #expect(!AccountStore.preview(.signedOut, isConfigured: false).isConfigured)

        let picking = AccountStore.preview(.needsHandle(TestData.newcomer), suggestedName: "Ava")
        #expect(picking.suggestedName == "Ava")
        #expect(await picking.checkHandle("ava") == .available)

        let signedIn = AccountStore.preview(.signedIn(TestData.ava))
        #expect(signedIn.user == TestData.ava)
    }
}

@MainActor
@Suite struct FriendsStoreTests {
    private func signedIn(_ configure: (inout FakeAPI.Answers) -> Void = { _ in }) async -> (FakeAPI, AccountStore, FriendsStore, EventLog) {
        let api = FakeAPI(token: "t", configure)
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        let friends = FriendsStore(api: api, account: account)
        let events = EventLog()
        friends.analytics = events.analytics
        return (api, account, friends, events)
    }

    @Test func refreshLoadsFriendsByNameAndTheCode() async {
        let (_, _, friends, _) = await signedIn { $0.friends = [TestData.noor, TestData.kai, TestData.bea] }
        #expect(!friends.hasLoaded)
        await friends.refresh()
        #expect(friends.friends.map(\.name) == ["bea", "Kai", "Noor"])
        #expect(friends.code == TestData.code)
        #expect(friends.hasLoaded)
        #expect(friends.problem == nil)
        #expect(!friends.isLoading)
    }

    @Test func nothingLoadsBeforeTheHandleIsPicked() async throws {
        let api = FakeAPI { $0.user = TestData.newcomer }
        let account = AccountStore(api: api, cache: TestData.cache())
        try await account.signIn(identityToken: "eyJ", authorizationCode: nil, displayName: nil)
        let friends = FriendsStore(api: api, account: account)
        await friends.refresh()
        #expect(!friends.hasLoaded)
        #expect(!api.calls.contains(.friends))
    }

    @Test func aFailedRefreshKeepsTheListAndSaysWhy() async {
        let (api, _, friends, _) = await signedIn { $0.friends = [TestData.noor] }
        await friends.refresh()
        api.set { $0.failures["friends"] = .offline }
        await friends.refresh()
        #expect(friends.friends == [TestData.noor])
        #expect(friends.problem == .offline)

        api.set { $0.failures = [:] }
        await friends.refresh()
        #expect(friends.problem == nil)
    }

    @Test func aRejectedSessionDuringRefreshSignsOut() async {
        let (api, account, friends, _) = await signedIn { $0.friends = [TestData.noor] }
        await friends.refresh()
        api.set { $0.failures["friends"] = .server(status: 401, code: .unauthorised, message: nil) }
        await friends.refresh()
        #expect(account.state == .signedOut)
        #expect(friends.friends.isEmpty)
        #expect(friends.problem == nil)
    }

    @Test func redeemingNormalisesTheCodeAndAddsTheFriend() async throws {
        let (api, _, friends, events) = await signedIn()
        await friends.refresh()
        let friend = try await friends.redeem(code: " kq7m-2xpa ")
        #expect(friend == TestData.noor)
        #expect(api.calls.last == .redeem("KQ7M2XPA"))
        #expect(friends.friends == [TestData.noor])
        #expect(events.count(.inviteRedeemed) == 1)

        // Again (the server allows it once it's the same person): still one row.
        _ = try await friends.redeem(code: "KQ7M2XPA")
        #expect(friends.friends.count == 1)
    }

    @Test func impossibleCodesAndYourOwnFailWithoutAsking() async throws {
        let (api, _, friends, events) = await signedIn()
        await friends.refresh()
        let before = api.calls.count
        await #expect(throws: APIError.server(status: 404, code: .codeNotFound, message: nil)) {
            try await friends.redeem(code: "KQ7M2XP0")
        }
        await #expect(throws: APIError.server(status: 404, code: .codeNotFound, message: nil)) {
            try await friends.redeem(code: "short")
        }
        await #expect(throws: APIError.server(status: 422, code: .ownCode, message: nil)) {
            try await friends.redeem(code: TestData.code.code.lowercased())
        }
        #expect(api.calls.count == before)
        #expect(events.count(.inviteRedeemed) == 0)
    }

    @Test func redeemErrorsComeThroughWithTheirCodes() async throws {
        let (api, _, friends, _) = await signedIn()
        api.set { $0.failures["redeem"] = .server(status: 410, code: .codeExpired, message: "Expired.") }
        do {
            try await friends.redeem(code: "KQ7M2XPA")
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .codeExpired)
        }
        #expect(friends.friends.isEmpty)
    }

    @Test func removingIsImmediateAndUndoneIfItFails() async throws {
        let (api, _, friends, _) = await signedIn { $0.friends = [TestData.noor, TestData.kai] }
        await friends.refresh()

        api.set { $0.failures["removeFriend"] = .offline }
        await #expect(throws: APIError.offline) {
            try await friends.remove(TestData.noor)
        }
        #expect(friends.friends.map(\.id) == [TestData.kai.id, TestData.noor.id])

        api.set { $0.failures = [:] }
        try await friends.remove(TestData.noor)
        #expect(friends.friends == [TestData.kai])
        #expect(api.calls.last == .removeFriend(TestData.noor.id))
    }

    @Test func blockingEndsTheFriendshipAndUnblockingUndoesTheBlock() async throws {
        let (api, _, friends, _) = await signedIn { $0.friends = [TestData.noor, TestData.kai] }
        await friends.refresh()

        try await friends.block(TestData.noor)
        #expect(api.calls.last == .block(TestData.noor.id))
        #expect(friends.friends == [TestData.kai])
        #expect(friends.blocked.map(\.id) == [TestData.noor.id])

        try await friends.unblock(TestData.noor)
        #expect(api.calls.last == .unblock(TestData.noor.id))
        #expect(friends.blocked.isEmpty)
        // Unblocking doesn't make you friends again.
        #expect(friends.friends == [TestData.kai])
    }

    @Test func theBlockedListLoads() async {
        let (_, _, friends, _) = await signedIn { $0.blocked = [TestData.kai, TestData.bea] }
        await friends.refreshBlocked()
        #expect(friends.blocked.map(\.name) == ["bea", "Kai"])
    }

    @Test func reportsCarryTheReason() async throws {
        let (api, _, friends, _) = await signedIn()
        try await friends.report(userId: TestData.kai.id, reason: .name)
        #expect(api.calls.last == .report(TestData.kai.id, .name, nil))
        try await friends.report(userId: TestData.kai.id, reason: .other, note: "Mean")
        #expect(api.calls.last == .report(TestData.kai.id, .other, "Mean"))
    }

    @Test func anInviteLinkWaitsToBeTakenOnce() async throws {
        let (_, _, friends, events) = await signedIn()
        let link = try #require(InviteLink(url: URL(string: "lockin://j/kq7m2xpa")!))
        friends.openInvite(link)
        #expect(friends.pendingInviteCode == "KQ7M2XPA")
        #expect(friends.takePendingInvite() == "KQ7M2XPA")
        #expect(friends.takePendingInvite() == nil)

        friends.noteInviteShared()
        #expect(events.count(.inviteShared) == 1)
    }

    @Test func previewsHoldTheirDataAndNeverFail() async throws {
        let account = AccountStore.preview(.signedIn(TestData.ava))
        let friends = FriendsStore.preview(account: account, friends: [TestData.noor, TestData.bea], redeems: TestData.kai)
        #expect(friends.friends.map(\.name) == ["bea", "Noor"])
        #expect(friends.code == PreviewAPI.sampleCode)
        #expect(friends.hasLoaded)
        await friends.refresh()
        #expect(friends.friends.count == 2)
        let added = try await friends.redeem(code: "KQ7M2XPB")
        #expect(added == TestData.kai)
    }
}
