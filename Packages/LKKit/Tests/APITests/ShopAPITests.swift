import Core
import Foundation
import Model
import Testing
@testable import API

/// M5's JSON (docs/milestones/M5.md), shaped exactly like the server builds it: `squadView` and
/// `squadLeaderboard` in server/src/squads.ts, `getShop` / `buyItem` / `myCosmetics` in
/// server/src/shop.ts, `importCoins` in server/src/accounts.ts, and `errorResponse` in
/// server/src/http.ts (extra fields first).
extension Sample {
    /// A teen sprout, happy: six days running, and today counts.
    static let m5Squad = """
    {"id":"Sq7Lb2Kd9P","name":"Library Goblins","ownerId":"u1Av4Nq8sT","members":[\
    {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","joinedAt":1791900000},\
    {"id":"u3Noor0001","handle":"noor.k","displayName":null,"avatarCode":"b2.c4.e2.h0","joinedAt":1791900060}],\
    "openSessionId":null,"muted":false,\
    "pet":{"species":"sprout","stage":2,"xp":1450,"mood":3,"progress":0.3541666666666667},\
    "streak":{"count":6,"countedToday":true,"doneToday":2,"needed":1},"tz":"Europe/London"}
    """

    /// A new squad's egg: tinted by its species already, hungry, no streak.
    static let eggSquad = """
    {"id":"Sq9Egg0001","name":"Night Owls","ownerId":"u1Av4Nq8sT","members":[\
    {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","joinedAt":1791900000}],\
    "openSessionId":null,"muted":false,\
    "pet":{"species":"ember","stage":0,"xp":25,"mood":1,"progress":0},\
    "streak":{"count":0,"countedToday":false,"doneToday":0,"needed":1},"tz":"Australia/Sydney"}
    """

    static let leaderboard = """
    {"weekStart":"2026-10-12","startsAt":1791759600,"endsAt":1792364400,"entries":[\
    {"userId":"u3Noor0001","minutes":310,"sessions":8},{"userId":"u1Av4Nq8sT","minutes":0,"sessions":0}]}
    """

    static let shop = """
    {"items":[{"id":"body.1","part":"body","option":1,"price":120,"plus":false},\
    {"id":"hat.2","part":"hat","option":2,"price":0,"plus":true}]}
    """
}

@Suite struct M5RequestTests {
    /// One case per route M5 adds or changes: the method, the path and the body.
    static let routes: [RequestTests.Route] = [
        .init(
            name: "createSquadInAZone",
            method: "POST",
            path: "/squads",
            reply: .ok(#"{"squad":\#(Sample.m5Squad)}"#),
            body: #"{"name":"Library Goblins","tz":"Europe/London"}"#
        ) { client in
            _ = try await client.createSquad(name: "Library Goblins", tz: "Europe/London")
        },
        .init(name: "createSquadWithoutAZone", method: "POST", path: "/squads", reply: .ok(#"{"squad":\#(Sample.m5Squad)}"#), body: #"{"name":"Library Goblins"}"#) { client in
            _ = try await client.createSquad(name: "Library Goblins", tz: nil)
        },
        .init(name: "leaderboard", method: "GET", path: "/squads/Sq7Lb2Kd9P/leaderboard", reply: .ok(Sample.leaderboard), body: nil) { client in
            _ = try await client.squadLeaderboard(id: "Sq7Lb2Kd9P", week: nil)
        },
        .init(name: "buy", method: "POST", path: "/shop/buy", reply: .ok(#"{"coins":20,"owned":["hat.3"]}"#), body: #"{"itemId":"hat.3"}"#) { client in
            _ = try await client.buy(itemId: "hat.3")
        },
        .init(name: "cosmetics", method: "GET", path: "/me/cosmetics", reply: .ok(#"{"owned":["colour.2","hat.1"]}"#), body: nil) { client in
            _ = try await client.cosmetics()
        },
        .init(
            name: "importCoins",
            method: "POST",
            path: "/me/coins/import",
            reply: .ok(#"{"user":\#(Sample.user),"owned":["colour.2"]}"#),
            body: #"{"coins":340,"owned":["colour.2","hat.4"]}"#
        ) { client in
            _ = try await client.importCoins(coins: 340, owned: ["colour.2", "hat.4"])
        },
    ]

    @Test(arguments: M5RequestTests.routes)
    func everyRouteSendsWhatTheContractSays(route: RequestTests.Route) async throws {
        let reply = route.reply
        let server = StubServer(token: "abc123") { _ in reply }
        try await route.call(server.client())

        #expect(server.requests.count == 1)
        let request = try #require(server.requests.first)
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

    @Test func aLeaderboardForAnotherWeekSaysWhichInTheQuery() async throws {
        let server = StubServer { _ in .ok(Sample.leaderboard) }
        _ = try await server.client().squadLeaderboard(id: "Sq7Lb2Kd9P", week: "2026-10-07")
        let request = try #require(server.requests.first)
        #expect(request.path == "/squads/Sq7Lb2Kd9P/leaderboard")
        #expect(request.url.query() == "week=2026-10-07")
    }

    @Test func theShopNeedsNoSignIn() async throws {
        let server = StubServer(token: nil) { _ in .ok(Sample.shop) }
        let items = try await server.client().shop()
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/shop")
        #expect(request.header("Authorization") == nil)
        #expect(items.count == 2)
    }
}

@Suite struct M5ResponseTests {
    @Test func aSquadCarriesItsPetStreakAndZone() async throws {
        let server = StubServer { _ in .ok(#"{"squads":[\#(Sample.m5Squad),\#(Sample.eggSquad)]}"#) }
        let squads = try await server.client().squads()

        let goblins = squads[0]
        #expect(goblins.pet.species == "sprout")
        #expect(goblins.pet.stage == 2)
        #expect(goblins.pet.xp == 1_450)
        #expect(goblins.pet.mood == 3)
        #expect(goblins.pet.petMood == .happy)
        #expect(abs(goblins.pet.progress - 0.354_166_666_666_666_7) < 0.000_000_001)
        #expect(goblins.pet.hasHatched)
        #expect(goblins.pet.code == PetCode(species: "sprout", stage: 2))
        #expect(goblins.pet.xpToNextStage == 3_000 - 1_450)
        #expect(goblins.streak == SquadStreak(count: 6, countedToday: true, doneToday: 2, needed: 1))
        #expect(goblins.tz == "Europe/London")

        // The egg already has its species, for its colour; it hatches on a finish, not on XP.
        let owls = squads[1]
        #expect(owls.pet.species == "ember")
        #expect(owls.pet.stage == 0)
        #expect(!owls.pet.hasHatched)
        #expect(owls.pet.code == PetCode(species: "ember", stage: 0))
        #expect(owls.pet.petMood == .hungry)
        #expect(owls.pet.progress == 0)
        #expect(owls.pet.xpToNextStage == nil)
        #expect(owls.streak.count == 0)
        #expect(owls.tz == "Australia/Sydney")
    }

    @Test func aSquadFromBeforeM5StillReads() async throws {
        // No mood, progress, streak or tz; an egg without a species.
        let server = StubServer { _ in .ok(#"{"squads":[\#(Sample.squad),\#(Sample.liveSquad)]}"#) }
        let squads = try await server.client().squads()
        #expect(squads[0].pet == SquadPet(species: nil, stage: 0, xp: 0))
        #expect(squads[0].pet.petMood == .content)
        #expect(squads[0].pet.code == PetCode(species: PetCode.defaultSpecies, stage: 0))
        #expect(squads[0].streak == SquadStreak())
        #expect(squads[0].tz == nil)
        // Progress comes from the XP then: 840 is a tenth of the way from 600 to 3000.
        #expect(abs(squads[1].pet.progress - 0.1) < 0.000_001)
        #expect(squads[1].pet.clampedProgress == squads[1].pet.progress)
    }

    @Test func oddStreakFieldsNeverCostTheSquad() throws {
        let json = Sample.m5Squad.replacingOccurrences(of: #""count":6"#, with: #""count":"six""#)
        let squad = try JSONDecoder().decode(Squad.self, from: Data(json.utf8))
        #expect(squad.streak.count == 0)
        #expect(squad.streak.countedToday)
        #expect(squad.streak.needed == 1)
    }

    @Test func squadsRoundTripThroughTheirOwnJSON() throws {
        let squad = try JSONDecoder().decode(Squad.self, from: Data(Sample.m5Squad.utf8))
        let again = try JSONDecoder().decode(Squad.self, from: JSONEncoder().encode(squad))
        #expect(again == squad)
    }

    @Test func theLeaderboardDecodes() async throws {
        let server = StubServer { _ in .ok(Sample.leaderboard) }
        let board = try await server.client().squadLeaderboard(id: "Sq7Lb2Kd9P", week: nil)
        #expect(board.weekStart == "2026-10-12")
        #expect(board.startDate == Date(timeIntervalSince1970: 1_791_759_600))
        #expect(board.endDate == Date(timeIntervalSince1970: 1_792_364_400))
        #expect(board.entries == [
            Leaderboard.Entry(userId: "u3Noor0001", minutes: 310, sessions: 8),
            Leaderboard.Entry(userId: "u1Av4Nq8sT", minutes: 0, sessions: 0),
        ])
        #expect(board.entry(for: "u1Av4Nq8sT")?.minutes == 0)
        #expect(board.entry(for: "nobody") == nil)
        #expect(board.totalMinutes == 310)
    }

    @Test func theShopDecodesAndSkipsWhatItCantRead() async throws {
        let server = StubServer { _ in .ok(Sample.shop) }
        let items = try await server.client().shop()
        #expect(items == [
            ShopItem(id: "body.1", part: .body, option: 1, price: 120, plus: false),
            ShopItem(id: "hat.2", part: .hat, option: 2, price: 0, plus: true),
        ])

        // A part a newer server added doesn't cost the rest of the shop.
        let newer = StubServer { _ in
            .ok(#"{"items":[{"id":"cape.1","part":"cape","option":1,"price":90,"plus":false},{"id":"eyes.1","part":"eyes","option":1,"price":60,"plus":false}]}"#)
        }
        let read = try await newer.client().shop()
        #expect(read.map(\.id) == ["eyes.1"])
    }

    @Test func buyingReturnsTheBalanceAndWhatYouOwn() async throws {
        let server = StubServer { _ in .ok(#"{"coins":20,"owned":["colour.2","hat.3"]}"#) }
        let result = try await server.client().buy(itemId: "hat.3")
        #expect(result.coins == 20)
        #expect(result.owned == ["colour.2", "hat.3"])
    }

    @Test func theImportReturnsTheAccountAndWhatItOwns() async throws {
        let server = StubServer { _ in .ok(#"{"user":\#(Sample.user),"owned":["colour.2"]}"#) }
        let result = try await server.client().importCoins(coins: 0, owned: [])
        #expect(result.user.id == "u1Av4Nq8sT")
        #expect(result.user.coins == 120)
        #expect(result.owned == ["colour.2"])
        #expect(try #require(server.requests.first).json()["coins"] as? Int == 0)
    }
}

@Suite struct M5ErrorTests {
    @Test func theShopsCodesMapToTheirCases() async throws {
        let cases: [(Int, String, APIErrorCode)] = [
            (402, "not_enough_coins", .notEnoughCoins),
            (402, "plus_required", .plusRequired),
            (409, "already_owned", .alreadyOwned),
            (404, "item_not_found", .itemNotFound),
        ]
        for (status, raw, expected) in cases {
            let server = StubServer { _ in .json(status: status, #"{"error":"x","code":"\#(raw)"}"#) }
            await #expect(throws: APIError.server(status: status, code: expected, message: "x")) {
                _ = try await server.client().buy(itemId: "hat.3")
            }
            #expect(APIErrorCode(rawValue: raw) == expected)
            #expect(expected.rawValue == raw)
            // Not a sign-out.
            #expect(server.tokens.load() != nil)
        }
    }

    @Test func aSecondImportIsAlreadyImported() async throws {
        let server = StubServer { _ in .json(status: 409, #"{"error":"Your coins are already here","code":"already_imported"}"#) }
        do {
            _ = try await server.client().importCoins(coins: 10, owned: [])
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .alreadyImported)
            #expect(error.status == 409)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func aLocklingWithAPartYouDontOwnSaysWhichPart() async throws {
        let server = StubServer { _ in
            .json(status: 403, #"{"itemId":"hat.3","error":"You don't own that item yet","code":"item_not_owned"}"#)
        }
        do {
            _ = try await server.client().updateMe(ProfileUpdate(avatarCode: "b0.c0.e0.h3"))
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .itemNotOwned)
            #expect(error.itemId == "hat.3")
            #expect(error.details == APIErrorDetails(itemId: "hat.3"))
            #expect(!error.isUnauthorised)
        }
    }

    @Test func theOtherM5CodesMapToTheirCases() {
        let cases: [(String, APIErrorCode)] = [
            ("already_imported", .alreadyImported), ("import_invalid", .importInvalid),
            ("item_not_owned", .itemNotOwned), ("week_invalid", .weekInvalid), ("tz_invalid", .tzInvalid),
        ]
        for (raw, code) in cases {
            #expect(APIErrorCode(rawValue: raw) == code)
            #expect(code.rawValue == raw)
            #expect(APIErrorCode.known.contains(code))
        }
    }
}
