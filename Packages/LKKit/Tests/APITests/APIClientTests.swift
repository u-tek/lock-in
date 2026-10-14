import Core
import Foundation
import Model
import Testing
@testable import API

@Suite struct RequestTests {
    @Test func signInSendsTheAppleTokenAndKeepsTheSession() async throws {
        let server = StubServer(token: nil) { _ in
            .ok(#"{"token":"n3wt0k3n","user":\#(Sample.newUser),"isNew":true}"#)
        }
        let result = try await server.client().signInWithApple(identityToken: "eyJ.apple", authorizationCode: "c0de", displayName: "Ava")

        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/apple")
        #expect(request.header("Authorization") == nil)
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("Accept") == "application/json")
        let body = try request.json()
        #expect(body["identityToken"] as? String == "eyJ.apple")
        #expect(body["authorizationCode"] as? String == "c0de")
        #expect(body["displayName"] as? String == "Ava")

        #expect(result.isNew)
        #expect(result.user.id == "u2Kq7Mx2Pa")
        #expect(result.user.handle == nil)
        #expect(server.tokens.load() == "n3wt0k3n")
    }

    @Test func signInLeavesOutWhatAppleDidNotShare() async throws {
        let server = StubServer(token: nil) { _ in
            .ok(#"{"token":"t","user":\#(Sample.user),"isNew":false}"#)
        }
        _ = try await server.client().signInWithApple(identityToken: "eyJ.apple", authorizationCode: nil, displayName: nil)
        let body = try #require(server.requests.first).json()
        #expect(Set(body.keys) == ["identityToken"])
    }

    @Test func authenticatedRequestsCarryTheBearerToken() async throws {
        let server = StubServer(token: "abc123") { _ in .ok(#"{"user":\#(Sample.user)}"#) }
        let user = try await server.client().me()
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/me")
        #expect(request.header("Authorization") == "Bearer abc123")
        #expect(request.body == nil || request.body?.isEmpty == true)
        #expect(user.handle == "ava")
    }

    /// One case per route in docs/milestones/M2.md: the method, the path and the body.
    struct Route: Sendable, CustomTestStringConvertible {
        var name: String
        var method: String
        var path: String
        var reply: StubServer.Reply
        /// The body's JSON, compared as objects; nil for none.
        var body: String?
        var call: @Sendable (APIClient) async throws -> Void

        var testDescription: String { name }
    }

    static let routes: [Route] = [
        Route(name: "me", method: "GET", path: "/me", reply: .ok(#"{"user":\#(Sample.user)}"#), body: nil) { client in
            _ = try await client.me()
        },
        Route(name: "updateMe", method: "PATCH", path: "/me", reply: .ok(#"{"user":\#(Sample.user)}"#), body: #"{"handle":"ava","displayName":"Ava"}"#) { client in
            _ = try await client.updateMe(ProfileUpdate(handle: "ava", displayName: "Ava"))
        },
        Route(name: "updateAvatar", method: "PATCH", path: "/me", reply: .ok(#"{"user":\#(Sample.user)}"#), body: #"{"avatarCode":"b1.c2.e3.h0"}"#) { client in
            _ = try await client.updateMe(ProfileUpdate(avatarCode: "b1.c2.e3.h0"))
        },
        Route(name: "handleAvailability", method: "GET", path: "/handles/noor.k", reply: .ok(#"{"available":true}"#), body: nil) { client in
            _ = try await client.handleAvailability("noor.k")
        },
        Route(name: "deleteMe", method: "DELETE", path: "/me", reply: .noContent, body: nil) { client in
            try await client.deleteMe()
        },
        Route(
            name: "registerDevice",
            method: "POST",
            path: "/devices",
            reply: .noContent,
            body: #"{"apnsToken":"a1b2","env":"sandbox","laEnabled":true,"frequentPushes":false,"tz":"Australia/Sydney"}"#
        ) { client in
            try await client.registerDevice(DeviceRegistration(apnsToken: "a1b2", env: .sandbox, laEnabled: true, frequentPushes: false, tz: "Australia/Sydney"))
        },
        Route(
            name: "registerDeviceWithPushToStart",
            method: "POST",
            path: "/devices",
            reply: .noContent,
            body: #"{"apnsToken":"a1b2","env":"production","pushToStartToken":"c3d4","laEnabled":false,"frequentPushes":true,"tz":"Europe/London"}"#
        ) { client in
            try await client.registerDevice(DeviceRegistration(apnsToken: "a1b2", env: .production, pushToStartToken: "c3d4", laEnabled: false, frequentPushes: true, tz: "Europe/London"))
        },
        Route(
            name: "registerDeviceWithQuietHours",
            method: "POST",
            path: "/devices",
            reply: .noContent,
            body: #"{"apnsToken":"a1b2","env":"sandbox","laEnabled":true,"frequentPushes":false,"tz":"Australia/Sydney","quietHours":{"start":1320,"end":420}}"#
        ) { client in
            try await client.registerDevice(DeviceRegistration(
                apnsToken: "a1b2", env: .sandbox, laEnabled: true, frequentPushes: false, tz: "Australia/Sydney",
                quietHours: .window(start: 1_320, end: 420)
            ))
        },
        Route(
            name: "registerDeviceWithQuietHoursOff",
            method: "POST",
            path: "/devices",
            reply: .noContent,
            body: #"{"apnsToken":"a1b2","env":"sandbox","laEnabled":true,"frequentPushes":false,"tz":"Australia/Sydney","quietHours":null}"#
        ) { client in
            try await client.registerDevice(DeviceRegistration(
                apnsToken: "a1b2", env: .sandbox, laEnabled: true, frequentPushes: false, tz: "Australia/Sydney",
                quietHours: .off
            ))
        },
        Route(name: "friends", method: "GET", path: "/friends", reply: .ok(#"{"friends":[\#(Sample.friend)]}"#), body: nil) { client in
            _ = try await client.friends()
        },
        Route(name: "friendCode", method: "POST", path: "/friends/code", reply: .ok(Sample.code), body: nil) { client in
            _ = try await client.friendCode()
        },
        Route(name: "redeem", method: "POST", path: "/friends/redeem/KQ7M2XPA", reply: .ok(#"{"friend":\#(Sample.friend)}"#), body: nil) { client in
            _ = try await client.redeemFriendCode("KQ7M2XPA")
        },
        Route(name: "removeFriend", method: "DELETE", path: "/friends/u3Noor0001", reply: .noContent, body: nil) { client in
            try await client.removeFriend(id: "u3Noor0001")
        },
        Route(name: "blocked", method: "GET", path: "/blocks", reply: .ok(#"{"blocked":[]}"#), body: nil) { client in
            _ = try await client.blocked()
        },
        Route(name: "block", method: "POST", path: "/blocks", reply: .noContent, body: #"{"userId":"u3Noor0001"}"#) { client in
            try await client.block(userId: "u3Noor0001")
        },
        Route(name: "unblock", method: "DELETE", path: "/blocks/u3Noor0001", reply: .noContent, body: nil) { client in
            try await client.unblock(userId: "u3Noor0001")
        },
        Route(name: "report", method: "POST", path: "/reports", reply: .noContent, body: #"{"userId":"u3Noor0001","reason":"harassment"}"#) { client in
            try await client.report(userId: "u3Noor0001", reason: .harassment, note: nil)
        },
        Route(name: "reportWithNote", method: "POST", path: "/reports", reply: .noContent, body: #"{"userId":"u3Noor0001","reason":"other","note":"Rude name"}"#) { client in
            try await client.report(userId: "u3Noor0001", reason: .other, note: "Rude name")
        },
    ]

    @Test(arguments: RequestTests.routes)
    func everyRouteSendsWhatTheContractSays(route: Route) async throws {
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
            #expect(try object(sent) == object(Data(expected.utf8)))
            #expect(request.header("Content-Type") == "application/json")
        } else {
            #expect(request.body == nil || request.body?.isEmpty == true)
        }
    }

    @Test func pathPartsCannotAddSegments() throws {
        let client = APIClient(baseURL: URL(string: "https://api.lockin.test")!, tokens: InMemoryTokenStore(token: "t"))
        let request = try client.request(.get, ["handles", "a/../me"])
        #expect(request.url?.path(percentEncoded: true) == "/handles/a%2F..%2Fme")
    }

    @Test func aBasePathIsKept() throws {
        let client = APIClient(baseURL: URL(string: "https://example.test/api")!, tokens: InMemoryTokenStore(token: "t"))
        let request = try client.request(.post, ["friends", "code"])
        #expect(request.url?.absoluteString == "https://example.test/api/friends/code")
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

@Suite struct ResponseTests {
    @Test func usersDecodeWithAndWithoutTheOptionalFields() async throws {
        let full = try JSONDecoder().decode(User.self, from: Data(Sample.user.utf8))
        #expect(full.id == "u1Av4Nq8sT")
        #expect(full.handle == "ava")
        #expect(full.displayName == "Ava")
        #expect(full.avatar == AvatarCode(body: 1, colour: 2, eyes: 3, hat: 0))
        #expect(full.coins == 120)
        #expect(full.plusUntilDate == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(full.createdDate == Date(timeIntervalSince1970: 1_791_900_000))

        let fresh = try JSONDecoder().decode(User.self, from: Data(Sample.newUser.utf8))
        #expect(fresh.handle == nil)
        #expect(fresh.displayName == nil)
        #expect(fresh.plusUntil == nil)
    }

    @Test func friendsListsAndCodesDecode() async throws {
        let server = StubServer { request in
            switch (request.method, request.path) {
            case ("GET", "/friends"): .ok(#"{"friends":[\#(Sample.friend),{"id":"u4","handle":null,"displayName":null,"avatarCode":"b9.zz","since":1.5}]}"#)
            case ("POST", "/friends/code"): .ok(Sample.code)
            case ("GET", "/blocks"): .ok(#"{"blocked":[\#(Sample.friend)]}"#)
            default: .noContent
            }
        }
        let client = server.client()

        let friends = try await client.friends()
        #expect(friends.count == 2)
        #expect(friends[0].name == "Noor")
        #expect(friends[0].handle == "noor.k")
        #expect(friends[0].sinceDate == Date(timeIntervalSince1970: 1_791_800_000))
        // An odd row still shows: unknown avatar parts fall back, a missing name reads "Friend".
        #expect(friends[1].name == "Friend")
        #expect(friends[1].avatar == AvatarCode(body: 9))

        let code = try await client.friendCode()
        #expect(code.code == "KQ7M2XPA")
        #expect(code.url == URL(string: "https://api.lockin.test/j/KQ7M2XPA"))
        #expect(code.expiryDate == Date(timeIntervalSince1970: 1_792_500_000))
        #expect(!code.isExpired(at: Date(timeIntervalSince1970: 1_792_499_999)))
        #expect(code.isExpired(at: Date(timeIntervalSince1970: 1_792_500_000)))

        let blocked = try await client.blocked()
        #expect(blocked.map(\.id) == ["u3Noor0001"])
    }

    struct AvailabilityCase: Sendable, CustomTestStringConvertible {
        var json: String
        var available: Bool
        var reason: HandleAvailability.Reason?

        var testDescription: String { json }
    }

    static let availabilityCases: [AvailabilityCase] = [
        AvailabilityCase(json: #"{"available":true}"#, available: true, reason: nil),
        AvailabilityCase(json: #"{"available":false,"reason":"taken"}"#, available: false, reason: .taken),
        AvailabilityCase(json: #"{"available":false,"reason":"invalid"}"#, available: false, reason: .invalid),
        AvailabilityCase(json: #"{"available":false,"reason":"not_allowed"}"#, available: false, reason: .notAllowed),
        // A reason from a newer server reads as none.
        AvailabilityCase(json: #"{"available":false,"reason":"something_new"}"#, available: false, reason: nil),
    ]

    @Test(arguments: ResponseTests.availabilityCases)
    func handleAvailabilityDecodes(_ example: AvailabilityCase) throws {
        let decoded = try JSONDecoder().decode(HandleAvailability.self, from: Data(example.json.utf8))
        #expect(decoded.available == example.available)
        #expect(decoded.reason == example.reason)
    }

    @Test func aBodyThatBreaksTheContractIsAnInvalidResponse() async {
        let server = StubServer { _ in .ok(#"{"user":{"id":"u1"}}"#) }
        await #expect(throws: APIError.invalidResponse) {
            try await server.client().me()
        }
    }
}

@Suite struct ErrorTests {
    @Test(arguments: APIErrorCode.known)
    func everyContractCodeIsRecognised(code: APIErrorCode) async throws {
        #expect(APIErrorCode(rawValue: code.rawValue) == code)
        let raw = code.rawValue
        let server = StubServer { _ in .json(status: 422, #"{"error":"Nope.","code":"\#(raw)"}"#) }
        do {
            _ = try await server.client().updateMe(ProfileUpdate(handle: "x"))
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error == .server(status: 422, code: code, message: "Nope."))
            #expect(error.code == code)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func redeemErrorsMapToTheirCodes() async throws {
        let cases: [(Int, String, APIErrorCode)] = [
            (404, "code_not_found", .codeNotFound),
            (410, "code_expired", .codeExpired),
            (422, "own_code", .ownCode),
            (409, "already_friends", .alreadyFriends),
            (403, "blocked", .blocked),
        ]
        for (status, raw, expected) in cases {
            let server = StubServer { _ in .json(status: status, #"{"error":"x","code":"\#(raw)"}"#) }
            await #expect(throws: APIError.server(status: status, code: expected, message: "x")) {
                try await server.client().redeemFriendCode("KQ7M2XPA")
            }
            // Not a sign-out: the session is fine.
            #expect(server.tokens.load() != nil)
        }
    }

    @Test func unknownCodesAndBareStatusesStillMap() {
        #expect(APIErrorCode(rawValue: "rate_limited") == .other("rate_limited"))
        #expect(APIError(status: 500, body: Data()) == .server(status: 500, code: .other("http_500"), message: nil))
        #expect(APIError(status: 401, body: Data("<html>".utf8)) == .server(status: 401, code: .unauthorised, message: nil))
        #expect(APIError(status: 429, body: Data()).errorDescription?.contains("wait") == true)
    }

    @Test func aRejectedSessionClearsTheToken() async throws {
        let server = StubServer(token: "expired") { _ in .json(status: 401, #"{"error":"Sign in again.","code":"unauthorised"}"#) }
        let client = server.client()
        #expect(client.hasSession)
        do {
            _ = try await client.friends()
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.isUnauthorised)
        }
        #expect(server.tokens.load() == nil)
        #expect(!client.hasSession)

        // With no token, nothing is sent at all.
        await #expect(throws: APIError.server(status: 401, code: .unauthorised, message: nil)) {
            try await client.friends()
        }
        #expect(server.requests.count == 1)
    }

    @Test func aRejectedAppleTokenIsNotASignOut() async throws {
        let server = StubServer(token: "still-good") { _ in .json(status: 401, #"{"error":"Bad token.","code":"apple_token_invalid"}"#) }
        do {
            _ = try await server.client().signInWithApple(identityToken: "bad", authorizationCode: nil, displayName: nil)
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .appleTokenInvalid)
            #expect(!error.isUnauthorised)
        }
        #expect(server.tokens.load() == "still-good")
    }

    @Test func deletingTheAccountForgetsTheToken() async throws {
        let server = StubServer(token: "abc") { _ in .noContent }
        try await server.client().deleteMe()
        #expect(server.tokens.load() == nil)
    }

    @Test func signOutForgetsTheTokenWithoutARequest() {
        let server = StubServer(token: "abc")
        let client = server.client()
        client.signOut()
        #expect(!client.hasSession)
        #expect(server.requests.isEmpty)
    }

    @Test func offlineIsItsOwnError() async {
        let server = StubServer { _ in .failure(.notConnectedToInternet) }
        await #expect(throws: APIError.offline) {
            try await server.client().friends()
        }
        let other = StubServer { _ in .failure(.badServerResponse) }
        await #expect(throws: APIError.network(code: URLError.Code.badServerResponse.rawValue)) {
            try await other.client().friends()
        }
    }

    @Test func noHostMeansNotConfigured() async {
        let client = APIClient(baseURL: nil, tokens: InMemoryTokenStore(token: "t"))
        #expect(!client.isConfigured)
        await #expect(throws: APIError.notConfigured) {
            try await client.me()
        }
    }
}

@Suite struct TokenStoreTests {
    @Test func inMemoryStoreRoundTrips() {
        let store = InMemoryTokenStore()
        #expect(store.load() == nil)
        store.save("abc")
        #expect(store.load() == "abc")
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func keychainStoreRoundTrips() {
        let service = "app.lockin.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service)
        defer { store.clear() }
        #expect(store.load() == nil)
        store.save("abc")
        #expect(store.load() == "abc")
        // A fresh store reads the Keychain itself. Test runners without a Keychain entitlement
        // can't write one, so only a value that did persist is checked.
        if let persisted = KeychainTokenStore(service: service).load() {
            #expect(persisted == "abc")
        }
        store.clear()
        #expect(store.load() == nil)
        #expect(KeychainTokenStore(service: service).load() == nil)
    }
}

@Suite struct DeviceRegistrationTests {
    private func registration(_ quietHours: DeviceQuietHours?) -> DeviceRegistration {
        DeviceRegistration(apnsToken: "a1b2", env: .sandbox, laEnabled: true, frequentPushes: false, tz: "Europe/London", quietHours: quietHours)
    }

    /// Left out, the server keeps what it has; null switches quiet hours off (docs/milestones/M4.md).
    @Test func quietHoursHaveThreeShapesOnTheWire() throws {
        let kept = try JSONSerialization.jsonObject(with: JSONEncoder().encode(registration(nil))) as? [String: Any]
        #expect(kept?.keys.contains("quietHours") == false)

        let off = try JSONSerialization.jsonObject(with: JSONEncoder().encode(registration(.off))) as? [String: Any]
        let null = off?["quietHours"] as? NSNull
        #expect(null != nil)

        let window = try JSONSerialization.jsonObject(with: JSONEncoder().encode(registration(.window(start: 1_320, end: 420)))) as? [String: Any]
        let sent = try #require(window?["quietHours"] as? [String: Any])
        #expect(sent["start"] as? Int == 1_320)
        #expect(sent["end"] as? Int == 420)
    }

    @Test func roundTripsEveryShape() throws {
        for quietHours in [nil, .off, .window(start: 0, end: 1_439)] as [DeviceQuietHours?] {
            let device = registration(quietHours)
            let decoded = try JSONDecoder().decode(DeviceRegistration.self, from: JSONEncoder().encode(device))
            #expect(decoded == device)
        }
    }
}
