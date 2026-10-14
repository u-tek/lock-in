import API
import Core
import Foundation
import Model
import Testing
@testable import Social

@MainActor
@Suite struct LeaderboardStoreTests {
    private let week = Leaderboard(
        weekStart: "2026-10-12",
        startsAt: 1_791_759_600,
        endsAt: 1_792_364_400,
        entries: [
            Leaderboard.Entry(userId: TestData.ava.id, minutes: 120, sessions: 3),
            Leaderboard.Entry(userId: TestData.noor.id, minutes: 45, sessions: 1),
        ]
    )

    private func signedIn(_ configure: (inout FakeAPI.Answers) -> Void = { _ in }) async -> (FakeAPI, AccountStore, SquadsStore) {
        let api = FakeAPI(token: "t", configure)
        let account = AccountStore(api: api, cache: TestData.cache())
        await account.restore()
        return (api, account, SquadsStore(api: api, account: account))
    }

    @Test func aSquadsWeekLoadsAndRanksItsMembers() async {
        let board = week
        let (api, _, squads) = await signedIn {
            $0.squads = [TestData.goblins]
            $0.leaderboards = [TestData.goblins.id: board]
        }
        await squads.refresh()
        // Before it loads: everyone, in joining order, without minutes.
        #expect(squads.ranking(of: TestData.goblins).map { $0.member.id } == [TestData.noor.id, TestData.ava.id])
        #expect(squads.ranking(of: TestData.goblins).allSatisfy { $0.entry == nil })

        let loaded = await squads.loadLeaderboard(for: TestData.goblins)
        #expect(loaded)
        #expect(api.calls.last == .squadLeaderboard(TestData.goblins.id, week: nil))
        #expect(squads.leaderboards[TestData.goblins.id] == board)
        let ranking = squads.ranking(of: TestData.goblins)
        #expect(ranking.map { $0.member.id } == [TestData.ava.id, TestData.noor.id])
        #expect(ranking.map { $0.entry?.minutes } == [120, 45])
    }

    @Test func someoneTheWeekDoesntListYetComesLast() async {
        var squad = TestData.goblins
        squad.members.append(SquadMember(id: TestData.kai.id, handle: "kai", displayName: "Kai", avatarCode: "b0.c7.e3.h2", joinedAt: 1_792_000_000))
        let board = week
        let (_, _, squads) = await signedIn {
            $0.squads = [squad]
            $0.leaderboards = [squad.id: board]
        }
        await squads.loadLeaderboard(for: squad)
        let ranking = squads.ranking(of: squad)
        #expect(ranking.map { $0.member.id } == [TestData.ava.id, TestData.noor.id, TestData.kai.id])
        #expect(ranking.last?.entry == nil)
    }

    @Test func aFailedLoadKeepsTheLastWeek() async {
        let board = week
        let (api, _, squads) = await signedIn { $0.leaderboards = [TestData.goblins.id: board] }
        await squads.loadLeaderboard(for: TestData.goblins)
        api.set { $0.failures["squadLeaderboard"] = .offline }
        let loaded = await squads.loadLeaderboard(for: TestData.goblins)
        #expect(!loaded)
        #expect(squads.leaderboards[TestData.goblins.id] == board)
    }

    @Test func signingOutForgetsTheWeeks() async {
        let board = week
        let (_, account, squads) = await signedIn { $0.leaderboards = [TestData.goblins.id: board] }
        await squads.loadLeaderboard(for: TestData.goblins)
        account.signOut()
        #expect(squads.leaderboards.isEmpty)
    }

    @Test func aNewSquadLivesByThePhonesTimeZone() async throws {
        let (api, _, squads) = await signedIn()
        let zone = try #require(TimeZone(identifier: "Australia/Sydney"))
        _ = try await squads.create(name: "Night Owls", timeZone: zone)
        #expect(api.calls.last == .createSquad("Night Owls", tz: "Australia/Sydney"))
    }
}
