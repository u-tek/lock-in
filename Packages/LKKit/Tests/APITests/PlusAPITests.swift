import Core
import Foundation
import Model
import Testing
@testable import API

// Lockin Plus on the API (docs/milestones/M7.md, "As built (server)"): Squad Boost, streak
// freezes, Demo Buddy's label and button, and `POST /me/plus/refresh`. JSON shaped exactly like
// `squadView` in server/src/squads.ts and `SquadStreak` in server/src/progress.ts.

extension Sample {
    /// A boosted squad: its teen sprout in the party hat (`pet.2`), a freeze filled the 12th, the
    /// caller has one left, and Demo Buddy is in it.
    static let boostedSquad = """
    {"id":"Sq7Lb2Kd9P","name":"Review Squad","ownerId":"u1Av4Nq8sT","members":[\
    {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","joinedAt":1791900000,"isBot":false},\
    {"id":"DemoBuddy0","handle":"demobuddy","displayName":"Demo Buddy","avatarCode":"b2.c5.e4.h3","joinedAt":1791900060,"isBot":true}],\
    "openSessionId":null,"muted":false,\
    "pet":{"species":"sprout","stage":2,"xp":1450,"mood":3,"progress":0.3541666666666667,"accessory":2},\
    "streak":{"count":6,"countedToday":true,"doneToday":1,"needed":1,"frozenDays":["2026-10-12"],"freezes":1},\
    "tz":"Europe/London","boosted":true}
    """

    /// The same squad once the boost lapsed: the server sends no accessory.
    static let unboostedSquad = """
    {"id":"Sq9Night01","name":"Night Owls","ownerId":"u1Av4Nq8sT","members":[\
    {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","joinedAt":1791900000,"isBot":false}],\
    "openSessionId":null,"muted":false,\
    "pet":{"species":"ember","stage":1,"xp":240,"mood":2,"progress":0.1,"accessory":null},\
    "streak":{"count":0,"countedToday":false,"doneToday":0,"needed":1,"frozenDays":[],"freezes":0},\
    "tz":"Europe/London","boosted":false}
    """
}

@Suite struct PlusRequestTests {
    static let routes: [RequestTests.Route] = [
        .init(
            name: "setPetAccessory",
            method: "PATCH",
            path: "/squads/Sq7Lb2Kd9P/pet",
            reply: .ok(#"{"squad":\#(Sample.boostedSquad)}"#),
            body: #"{"accessory":2}"#
        ) { client in
            _ = try await client.setPetAccessory(squadId: "Sq7Lb2Kd9P", accessory: 2)
        },
        // Taking it off sends null: the server turns a missing key down.
        .init(
            name: "takePetAccessoryOff",
            method: "PATCH",
            path: "/squads/Sq7Lb2Kd9P/pet",
            reply: .ok(#"{"squad":\#(Sample.unboostedSquad)}"#),
            body: #"{"accessory":null}"#
        ) { client in
            _ = try await client.setPetAccessory(squadId: "Sq7Lb2Kd9P", accessory: nil)
        },
        .init(
            name: "askDemoBuddy",
            method: "POST",
            path: "/squads/Sq7Lb2Kd9P/demo-buddy/lock-in",
            reply: .ok(#"{"session":\#(Sample.session)}"#),
            body: nil
        ) { client in
            _ = try await client.askDemoBuddy(squadId: "Sq7Lb2Kd9P")
        },
        .init(name: "refreshPlus", method: "POST", path: "/me/plus/refresh", reply: .ok(#"{"user":\#(Sample.user)}"#), body: nil) { client in
            _ = try await client.refreshPlus()
        },
    ]

    @Test(arguments: PlusRequestTests.routes)
    func everyRouteSendsWhatTheContractSays(route: RequestTests.Route) async throws {
        let reply = route.reply
        let server = StubServer(token: "abc123") { _ in reply }
        try await route.call(server.client())

        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == route.method)
        #expect(request.path == route.path)
        #expect(request.header("Authorization") == "Bearer abc123")
        if let expected = route.body {
            let sent = try #require(request.body)
            let sentObject = try #require(JSONSerialization.jsonObject(with: sent) as? NSDictionary)
            let expectedObject = try #require(JSONSerialization.jsonObject(with: Data(expected.utf8)) as? NSDictionary)
            #expect(sentObject == expectedObject)
        } else {
            #expect(request.body == nil || request.body?.isEmpty == true)
        }
    }

    @Test func theAccessoryKeyIsAlwaysSent() throws {
        let off = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PetAccessoryRequest(accessory: nil))) as? [String: Any]
        #expect(off?.keys.contains("accessory") == true)
        #expect(off?["accessory"] is NSNull)
        let on = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PetAccessoryRequest(accessory: 6))) as? [String: Any]
        #expect(on?["accessory"] as? Int == 6)
    }

    @Test func demoBuddysSessionAndTheRefreshedAccountDecode() async throws {
        let buddy = StubServer { _ in .ok(#"{"session":\#(Sample.session)}"#) }
        let session = try await buddy.client().askDemoBuddy(squadId: "Sq7Lb2Kd9P")
        #expect(session.id == "r7Kq2xP9aL")
        #expect(session.squadId == "Sq7Lb2Kd9P")
        #expect(!session.isEnded)

        let refresh = StubServer { _ in .ok(#"{"user":\#(Sample.user)}"#) }
        let user = try await refresh.client().refreshPlus()
        #expect(user.plusUntil == 1_800_000_000)
    }
}

@Suite struct PlusResponseTests {
    @Test func boostFreezesAndTheBotDecode() async throws {
        let server = StubServer { _ in .ok(#"{"squads":[\#(Sample.boostedSquad),\#(Sample.unboostedSquad)]}"#) }
        let squads = try await server.client().squads()
        let review = squads[0]
        #expect(review.boosted)
        #expect(review.pet.accessory == 2)
        #expect(review.pet.wornAccessory == .partyHat)
        #expect(review.pet.code == PetCode(species: "sprout", stage: 2, accessory: 2))
        #expect(review.pet.code.code == "sprout.2.a2")
        #expect(review.streak.frozenDays == ["2026-10-12"])
        #expect(review.streak.freezes == 1)
        #expect(review.members.map(\.isBot) == [false, true])
        #expect(review.hasBot)
        #expect(review.member(id: "DemoBuddy0")?.name == "Demo Buddy")

        let owls = squads[1]
        #expect(!owls.boosted)
        #expect(owls.pet.accessory == nil)
        #expect(owls.pet.code == PetCode(species: "ember", stage: 1))
        #expect(owls.streak.frozenDays.isEmpty)
        #expect(owls.streak.freezes == 0)
        #expect(!owls.hasBot)
    }

    /// From a server older than M7, or with an odd value, the new fields read as their defaults
    /// and the squad still shows.
    @Test func olderOrOddAnswersFallBack() async throws {
        let odd = """
        {"id":"SqOdd00001","name":"Odd","ownerId":"u1Av4Nq8sT","members":[\
        {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","joinedAt":1791900000,"isBot":"no"}],\
        "openSessionId":null,"muted":false,\
        "pet":{"species":"puff","stage":3,"xp":5000,"accessory":"hat"},\
        "streak":{"count":2,"countedToday":false,"doneToday":0,"needed":1,"frozenDays":"2026-10-12","freezes":"two"},\
        "boosted":"yes"}
        """
        let server = StubServer { _ in .ok(#"{"squads":[\#(Sample.squad),\#(odd)]}"#) }
        let squads = try await server.client().squads()
        #expect(squads.count == 2)
        for squad in squads {
            #expect(!squad.boosted)
            #expect(squad.pet.accessory == nil)
            #expect(squad.streak.frozenDays.isEmpty)
            #expect(squad.streak.freezes == 0)
            #expect(squad.members.allSatisfy { !$0.isBot })
        }
        #expect(squads[1].streak.count == 2)
    }

    /// An accessory this version can't draw is kept in the code but worn as nothing; one the
    /// server couldn't send (0, or past 99) isn't kept at all.
    @Test func unknownAccessoriesAreKeptButNotWorn() {
        #expect(SquadPet(species: "sprout", stage: 2, accessory: 9).code.code == "sprout.2.a9")
        #expect(SquadPet(species: "sprout", stage: 2, accessory: 9).wornAccessory == nil)
        #expect(SquadPet(species: "sprout", stage: 2, accessory: 0).code.code == "sprout.2")
        #expect(SquadPet(species: "sprout", stage: 2, accessory: 100).code.accessory == nil)
    }

    @Test func boostAndAccessoryErrorsMap() {
        let boost = APIError(status: 402, body: Data(#"{"error":"Squad Boost needs Plus","code":"plus_required","limit":"boost"}"#.utf8))
        #expect(boost.code == .plusRequired)
        #expect(boost.plusLimit == "boost")
        #expect(boost.errorDescription?.contains("Lockin Plus") == true)

        let invalid = APIError(status: 422, body: Data(#"{"error":"nope","code":"accessory_invalid"}"#.utf8))
        #expect(invalid.code == .accessoryInvalid)
        #expect(APIErrorCode(rawValue: "accessory_invalid") == .accessoryInvalid)
        #expect(APIErrorCode.known.contains(.accessoryInvalid))
    }

    @Test func plusOnTheAccountRunsUntilPlusUntil() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var user = User(id: "u1", handle: "ava", displayName: nil, avatarCode: "b0.c0.e0.h0", createdAt: 0)
        #expect(!user.hasPlus(at: now))
        user.plusUntil = 1_800_000_001
        #expect(user.hasPlus(at: now))
        user.plusUntil = 1_800_000_000
        #expect(!user.hasPlus(at: now))
        // Lifetime: 9999-12-31.
        user.plusUntil = 253_402_300_799
        #expect(user.hasPlus(at: now))
        user.plusUntil = Double.nan
        #expect(!user.hasPlus(at: now))
    }
}

@Suite struct StreakWeekTests {
    private typealias Mark = SquadStreak.Day.Mark

    private func marks(_ streak: SquadStreak, today: String = "2026-10-14") -> [Mark] {
        streak.days(endingOn: today).map(\.mark)
    }

    @Test func aStreakCountedTodayFillsTheWeekBackwards() {
        let streak = SquadStreak(count: 3, countedToday: true)
        #expect(marks(streak) == [.missed, .missed, .missed, .missed, .counted, .counted, .counted])
        let days = streak.days(endingOn: "2026-10-14")
        #expect(days.map(\.day) == ["2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12", "2026-10-13", "2026-10-14"])
        // The 14th of October 2026 is a Wednesday (Calendar's 4).
        #expect(days.last?.weekday == 4)
        #expect(days.first?.weekday == 5)
    }

    @Test func todayWaitsUntilItCounts() {
        let streak = SquadStreak(count: 2, countedToday: false)
        #expect(marks(streak) == [.missed, .missed, .missed, .missed, .counted, .counted, .pending])
    }

    /// A frozen day keeps the streak going without adding to its count.
    @Test func aFreezeBridgesAGap() {
        let streak = SquadStreak(count: 3, countedToday: true, frozenDays: ["2026-10-12"], freezes: 1)
        #expect(marks(streak) == [.missed, .missed, .missed, .counted, .frozen, .counted, .counted])

        // Frozen yesterday, today not done yet: the streak's last day is the frozen one.
        let waiting = SquadStreak(count: 4, countedToday: false, frozenDays: ["2026-10-13"])
        #expect(marks(waiting) == [.missed, .counted, .counted, .counted, .counted, .frozen, .pending])
    }

    /// A freeze from a streak that broke later still shows as frozen.
    @Test func anOldFreezeStillShows() {
        let streak = SquadStreak(count: 0, countedToday: false, frozenDays: ["2026-10-09"])
        #expect(marks(streak) == [.missed, .frozen, .missed, .missed, .missed, .missed, .pending])
    }

    @Test func aLongStreakFillsTheWholeWeek() {
        let streak = SquadStreak(count: 40, countedToday: true, frozenDays: ["2026-10-10"])
        #expect(marks(streak) == [.counted, .counted, .frozen, .counted, .counted, .counted, .counted])
    }

    @Test func badDaysGiveNothing() {
        let streak = SquadStreak(count: 3, countedToday: true)
        #expect(streak.days(endingOn: "yesterday").isEmpty)
        #expect(streak.days(endingOn: "2026-02-30").isEmpty)
        #expect(streak.days(endingOn: "2026-10-14", length: 0).isEmpty)
        #expect(streak.days(endingOn: "2026-01-02").map(\.day) == [
            "2025-12-27", "2025-12-28", "2025-12-29", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02",
        ])
    }

    @Test func todayIsTheSquadsDay() {
        // 23:30 UTC on the 14th is already the 15th in London (summer time) and Sydney, and
        // still the 14th in Los Angeles.
        let instant = Date(timeIntervalSince1970: 1_792_020_600)
        #expect(SquadStreak.day(of: instant, in: TimeZone(identifier: "Europe/London")!) == "2026-10-15")
        #expect(SquadStreak.day(of: instant, in: TimeZone(identifier: "Australia/Sydney")!) == "2026-10-15")
        #expect(SquadStreak.day(of: instant, in: TimeZone(identifier: "UTC")!) == "2026-10-14")
        #expect(SquadStreak.day(of: instant, in: TimeZone(identifier: "America/Los_Angeles")!) == "2026-10-14")
    }
}
