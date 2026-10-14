import Core
import Foundation
import Model
import Testing
@testable import API

/// JSON shaped exactly like the server's response builders (docs/milestones/M3.md): `squadView` in
/// server/src/squads.ts, `joined` / `sessionView` / `contentState` / `stateMessage` in
/// server/src/room.ts, and `errorResponse` in server/src/http.ts (extra fields first).
extension Sample {
    static let squad = """
    {"id":"Sq7Lb2Kd9P","name":"Library Goblins","ownerId":"u1Av4Nq8sT","members":[\
    {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","joinedAt":1791900000},\
    {"id":"u3Noor0001","handle":"noor.k","displayName":null,"avatarCode":"b2.c4.e2.h0","joinedAt":1791900060}],\
    "openSessionId":null,"muted":false,"pet":{"species":null,"stage":0,"xp":0}}
    """

    /// Someone's locked in, the pet has hatched, the owner's account is mid-deletion, and you muted it.
    static let liveSquad = """
    {"id":"Sq9Night01","name":"Night Owls","ownerId":null,"members":[\
    {"id":"u3Noor0001","handle":"noor.k","displayName":"Noor","avatarCode":"b2.c4.e2.h0","joinedAt":1791800000}],\
    "openSessionId":"r7Kq2xP9aL","muted":true,"pet":{"species":"fox","stage":2,"xp":840}}
    """

    static let session = """
    {"id":"r7Kq2xP9aL","squadId":"Sq7Lb2Kd9P","hostId":"u1Av4Nq8sT","status":"open","createdAt":1791900000}
    """

    static let contentState = """
    {"v":1,"m":[{"i":"u1Av4Nq8sT","n":"Ava","a":"b1.c2.e3.h0","s":0,"b":1791900000,"e":1791901500}]}
    """

    /// Ava paused, Noor focusing; the pet and a cheer from Noor to Ava.
    static let pausedState = """
    {"v":4,"m":[{"i":"u1Av4Nq8sT","n":"Ava","a":"b1.c2.e3.h0","s":2,"b":1791900000,"e":1791901500,"q":1791900600},\
    {"i":"u3Noor0001","n":"noor.k","a":"b2.c4.e2.h0","s":0,"b":1791900030,"e":1791903030}],\
    "p":{"k":"fox.2","md":3,"x":0.4},"c":{"f":"u3Noor0001","t":"u1Av4Nq8sT","k":3,"at":1791900650}}
    """

    static let joined = """
    {"session":\(Sample.session),"attributes":{"sid":"r7Kq2xP9aL","me":"u1Av4Nq8sT","sq":"Library Goblins"},"contentState":\(Sample.contentState)}
    """

    static let soloJoined = """
    {"session":{"id":"s0L0x2Kq9A","squadId":null,"hostId":"u1Av4Nq8sT","status":"open","createdAt":1791900000},\
    "attributes":{"sid":"s0L0x2Kq9A","me":"u1Av4Nq8sT"},"contentState":\(Sample.contentState)}
    """
}

@Suite struct SquadRequestTests {
    /// One case per route in docs/milestones/M3.md: the method, the path and the body.
    static let routes: [RequestTests.Route] = [
        .init(name: "squads", method: "GET", path: "/squads", reply: .ok(#"{"squads":[\#(Sample.squad)]}"#), body: nil) { client in
            _ = try await client.squads()
        },
        .init(name: "createSquad", method: "POST", path: "/squads", reply: .ok(#"{"squad":\#(Sample.squad)}"#), body: #"{"name":"Library Goblins"}"#) { client in
            _ = try await client.createSquad(name: "Library Goblins")
        },
        .init(name: "renameSquad", method: "PATCH", path: "/squads/Sq7Lb2Kd9P", reply: .ok(#"{"squad":\#(Sample.squad)}"#), body: #"{"name":"Night Owls"}"#) { client in
            _ = try await client.renameSquad(id: "Sq7Lb2Kd9P", name: "Night Owls")
        },
        .init(name: "squadInvite", method: "POST", path: "/squads/Sq7Lb2Kd9P/invite", reply: .ok(Sample.code), body: nil) { client in
            _ = try await client.squadInvite(id: "Sq7Lb2Kd9P")
        },
        .init(name: "joinSquad", method: "POST", path: "/squads/join/KQ7M2XPA", reply: .ok(#"{"squad":\#(Sample.squad)}"#), body: nil) { client in
            _ = try await client.joinSquad(code: "KQ7M2XPA")
        },
        .init(name: "setSquadMuted", method: "PATCH", path: "/squads/Sq7Lb2Kd9P/members/me", reply: .ok(#"{"squad":\#(Sample.squad)}"#), body: #"{"muted":true}"#) { client in
            _ = try await client.setSquadMuted(id: "Sq7Lb2Kd9P", muted: true)
        },
        .init(name: "leaveSquad", method: "DELETE", path: "/squads/Sq7Lb2Kd9P/members/me", reply: .noContent, body: nil) { client in
            try await client.leaveSquad(id: "Sq7Lb2Kd9P")
        },
        .init(name: "startSquadSession", method: "POST", path: "/sessions", reply: .ok(Sample.joined), body: #"{"squadId":"Sq7Lb2Kd9P","minutes":25}"#) { client in
            _ = try await client.startSession(squadId: "Sq7Lb2Kd9P", minutes: 25)
        },
        .init(name: "startSoloSession", method: "POST", path: "/sessions", reply: .ok(Sample.soloJoined), body: #"{"minutes":50}"#) { client in
            _ = try await client.startSession(squadId: nil, minutes: 50)
        },
        .init(name: "joinSession", method: "POST", path: "/sessions/r7Kq2xP9aL/join", reply: .ok(Sample.joined), body: #"{"minutes":90}"#) { client in
            _ = try await client.joinSession(id: "r7Kq2xP9aL", minutes: 90)
        },
        .init(
            name: "uploadLiveActivityToken",
            method: "POST",
            path: "/sessions/r7Kq2xP9aL/la-token",
            reply: .noContent,
            body: #"{"token":"80a1b2c3d4","env":"production"}"#
        ) { client in
            try await client.uploadLiveActivityToken(sessionId: "r7Kq2xP9aL", token: "80a1b2c3d4", env: .production)
        },
        .init(name: "pause", method: "POST", path: "/sessions/r7Kq2xP9aL/pause", reply: .ok(#"{"contentState":\#(Sample.pausedState)}"#), body: nil) { client in
            _ = try await client.pauseSession(id: "r7Kq2xP9aL")
        },
        .init(name: "resume", method: "POST", path: "/sessions/r7Kq2xP9aL/resume", reply: .ok(#"{"contentState":\#(Sample.contentState)}"#), body: nil) { client in
            _ = try await client.resumeSession(id: "r7Kq2xP9aL")
        },
        .init(name: "end", method: "POST", path: "/sessions/r7Kq2xP9aL/end", reply: .ok(#"{"contentState":\#(Sample.contentState)}"#), body: nil) { client in
            _ = try await client.endSession(id: "r7Kq2xP9aL")
        },
        .init(name: "slip", method: "POST", path: "/sessions/r7Kq2xP9aL/slip", reply: .ok(#"{"contentState":\#(Sample.contentState)}"#), body: nil) { client in
            _ = try await client.slipSession(id: "r7Kq2xP9aL")
        },
        .init(name: "cheer", method: "POST", path: "/sessions/r7Kq2xP9aL/cheer", reply: .noContent, body: #"{"to":"u3Noor0001","kind":3}"#) { client in
            try await client.cheer(sessionId: "r7Kq2xP9aL", to: "u3Noor0001", kind: 3)
        },
        .init(
            name: "session",
            method: "GET",
            path: "/sessions/r7Kq2xP9aL",
            reply: .ok(#"{"session":\#(Sample.session),"contentState":\#(Sample.contentState)}"#),
            body: nil
        ) { client in
            _ = try await client.session(id: "r7Kq2xP9aL")
        },
        .init(name: "signOutSession", method: "DELETE", path: "/auth/session", reply: .noContent, body: nil) { client in
            try await client.signOutSession()
        },
    ]

    @Test(arguments: SquadRequestTests.routes)
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
            #expect(try object(sent) == object(Data(expected.utf8)))
            #expect(request.header("Content-Type") == "application/json")
        } else {
            #expect(request.body == nil || request.body?.isEmpty == true)
        }
    }

    @Test func signingOutTheSessionForgetsTheToken() async throws {
        let server = StubServer(token: "abc123") { _ in .noContent }
        let client = server.client()
        try await client.signOutSession()
        #expect(!client.hasSession)
        #expect(server.requests.first?.header("Authorization") == "Bearer abc123")

        // Offline, the server can't be told: the token stays for the caller to forget.
        let offline = StubServer(token: "abc123") { _ in .failure(.notConnectedToInternet) }
        await #expect(throws: APIError.offline) {
            try await offline.client().signOutSession()
        }
        #expect(offline.tokens.load() == "abc123")
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

@Suite struct SquadResponseTests {
    @Test func squadsDecodeWithEveryField() async throws {
        let server = StubServer { _ in .ok(#"{"squads":[\#(Sample.squad),\#(Sample.liveSquad)]}"#) }
        let squads = try await server.client().squads()
        #expect(squads.count == 2)

        let goblins = squads[0]
        #expect(goblins.id == "Sq7Lb2Kd9P")
        #expect(goblins.name == "Library Goblins")
        #expect(goblins.ownerId == "u1Av4Nq8sT")
        #expect(goblins.isOwned(by: "u1Av4Nq8sT"))
        #expect(!goblins.isOwned(by: "u3Noor0001"))
        #expect(goblins.openSessionId == nil)
        #expect(!goblins.isLive)
        #expect(!goblins.muted)
        #expect(goblins.pet == SquadPet(species: nil, stage: 0, xp: 0))
        #expect(!goblins.pet.hasHatched)
        #expect(goblins.members.map(\.id) == ["u1Av4Nq8sT", "u3Noor0001"])
        #expect(goblins.members[0].name == "Ava")
        #expect(goblins.members[0].avatar == AvatarCode(body: 1, colour: 2, eyes: 3, hat: 0))
        #expect(goblins.members[0].joinedDate == Date(timeIntervalSince1970: 1_791_900_000))
        // No display name: the handle.
        #expect(goblins.members[1].name == "noor.k")
        #expect(goblins.member(id: "u3Noor0001")?.joinedAt == 1_791_900_060)

        let owls = squads[1]
        #expect(owls.ownerId == nil)
        #expect(!owls.isOwned(by: nil))
        #expect(owls.openSessionId == "r7Kq2xP9aL")
        #expect(owls.isLive)
        #expect(owls.muted)
        #expect(owls.pet == SquadPet(species: "fox", stage: 2, xp: 840))
        #expect(owls.pet.hasHatched)
    }

    @Test func aMemberWithNoNamesIsALockling() {
        let member = SquadMember(id: "u9", handle: nil, displayName: "", avatarCode: "b0.c0.e0.h0", joinedAt: 0)
        #expect(member.name == "Lockling")
    }

    @Test func joiningReturnsWhatActivityKitNeeds() async throws {
        let server = StubServer { _ in .ok(Sample.joined) }
        let joined = try await server.client().startSession(squadId: "Sq7Lb2Kd9P", minutes: 25)
        #expect(joined.session == SessionInfo(id: "r7Kq2xP9aL", squadId: "Sq7Lb2Kd9P", hostId: "u1Av4Nq8sT", status: "open", createdAt: 1_791_900_000))
        #expect(!joined.session.isEnded)
        #expect(joined.attributes == LockinAttributes(sid: "r7Kq2xP9aL", me: "u1Av4Nq8sT", sq: "Library Goblins"))
        #expect(joined.contentState.v == 1)
        let me = try #require(joined.contentState.member(id: joined.attributes.me))
        #expect(me.state == .focusing)
        #expect(me.b == 1_791_900_000)
        #expect(me.e == 1_791_901_500)
        #expect(me.q == nil)
        #expect(joined.contentState.p == nil)
        #expect(joined.contentState.c == nil)
        #expect(joined.attributes.fitsPayloadBudget(joined.contentState))

        // Solo: no squad, no squad name.
        let solo = try JSONDecoder().decode(JoinedSession.self, from: Data(Sample.soloJoined.utf8))
        #expect(solo.session.squadId == nil)
        #expect(solo.attributes.sq == nil)
        #expect(solo.attributes.isSolo)
    }

    @Test func memberActionsReturnTheRoomsState() async throws {
        let server = StubServer { _ in .ok(#"{"contentState":\#(Sample.pausedState)}"#) }
        let state = try await server.client().pauseSession(id: "r7Kq2xP9aL")
        #expect(state.v == 4)
        let ava = try #require(state.member(id: "u1Av4Nq8sT"))
        #expect(ava.state == .paused)
        #expect(ava.q == 1_791_900_600)
        #expect(ava.remaining(at: Date(timeIntervalSince1970: 1_791_999_999)) == 900)
        #expect(state.member(id: "u3Noor0001")?.state == .focusing)
        #expect(state.p == LockinAttributes.ContentState.Pet(k: "fox.2", md: 3, x: 0.4))
        #expect(state.c == LockinAttributes.ContentState.Cheer(f: "u3Noor0001", t: "u1Av4Nq8sT", k: 3, at: 1_791_900_650))
    }

    @Test func aSessionSnapshotCanHaveNoStateLeft() async throws {
        let open = StubServer { _ in .ok(#"{"session":\#(Sample.session),"contentState":\#(Sample.contentState)}"#) }
        let current = try await open.client().session(id: "r7Kq2xP9aL")
        #expect(current.session.status == SessionInfo.open)
        #expect(current.contentState?.v == 1)

        // A day after the room ended, the state is gone; a deleted host reads as no host.
        let gone = StubServer { _ in
            .ok(#"{"session":{"id":"r7Kq2xP9aL","squadId":"Sq7Lb2Kd9P","hostId":null,"status":"ended","createdAt":1791900000},"contentState":null}"#)
        }
        let ended = try await gone.client().session(id: "r7Kq2xP9aL")
        #expect(ended.session.isEnded)
        #expect(ended.session.hostId == "")
        #expect(ended.contentState == nil)
    }

    @Test func aBrokenSquadIsAnInvalidResponse() async {
        let server = StubServer { _ in .ok(#"{"squad":{"id":"Sq7Lb2Kd9P","name":"x"}}"#) }
        await #expect(throws: APIError.invalidResponse) {
            try await server.client().createSquad(name: "x")
        }
    }
}

@Suite struct SquadErrorTests {
    @Test func aFreeLimitSaysWhichOne() async throws {
        for limit in ["squads", "members"] {
            let server = StubServer { _ in
                .json(status: 402, #"{"limit":"\#(limit)","error":"Lockin Plus lets you be in up to 3 squads","code":"plus_required"}"#)
            }
            do {
                _ = try await server.client().joinSquad(code: "KQ7M2XPA")
                Issue.record("Expected an error")
            } catch let error as APIError {
                #expect(error.code == .plusRequired)
                #expect(error.status == 402)
                #expect(error.plusLimit == limit)
                #expect(error.details == APIErrorDetails(limit: limit))
                #expect(error.errorDescription?.isEmpty == false)
                #expect(!error.isUnauthorised)
            }
        }
    }

    @Test func alreadyInASessionSaysWhichOne() async throws {
        let server = StubServer { _ in
            .json(status: 409, #"{"sessionId":"r7Kq2xP9aL","error":"You're already in a session. End it first.","code":"already_in_session"}"#)
        }
        do {
            _ = try await server.client().startSession(squadId: "Sq7Lb2Kd9P", minutes: 25)
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .alreadyInSession)
            #expect(error.sessionId == "r7Kq2xP9aL")
            #expect(error.plusLimit == nil)
            #expect(error == .server(
                status: 409,
                code: .alreadyInSession,
                message: "You're already in a session. End it first.",
                details: APIErrorDetails(sessionId: "r7Kq2xP9aL")
            ))
        }
    }

    @Test func aCheerTooSoonSaysHowLongToWait() async throws {
        let server = StubServer { _ in
            .json(status: 429, #"{"retryAfter":7,"error":"One cheer every 10 seconds","code":"cheer_too_soon"}"#)
        }
        do {
            try await server.client().cheer(sessionId: "r7Kq2xP9aL", to: "u3Noor0001", kind: 2)
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .cheerTooSoon)
            #expect(error.retryAfter == 7)
        }
    }

    @Test func oddExtraFieldsNeverCostTheCode() {
        let error = APIError(status: 402, body: Data(#"{"limit":6,"retryAfter":"soon","error":"Full","code":"plus_required"}"#.utf8))
        #expect(error.code == .plusRequired)
        #expect(error.plusLimit == nil)
        #expect(error.retryAfter == nil)
        // A limit on anything but plus_required isn't a paywall.
        let other = APIError(status: 409, body: Data(#"{"limit":"squads","error":"x","code":"room_full"}"#.utf8))
        #expect(other.plusLimit == nil)
        #expect(APIError.offline.details == .empty)
    }

    @Test func theRoomsCodesMapToTheirCases() {
        let cases: [(String, APIErrorCode)] = [
            ("not_owner", .notOwner), ("not_member", .notMember), ("friend_code", .friendCode),
            ("already_member", .alreadyMember), ("session_ended", .sessionEnded),
            ("session_not_found", .sessionNotFound), ("room_full", .roomFull), ("bad_state", .badState),
            ("token_invalid", .tokenInvalid), ("cheer_invalid", .cheerInvalid),
            ("minutes_invalid", .minutesInvalid), ("try_again", .tryAgain),
        ]
        for (raw, code) in cases {
            #expect(APIErrorCode(rawValue: raw) == code)
            #expect(code.rawValue == raw)
        }
    }
}

@Suite struct LiveViewTests {
    @Test func stateMessagesDecode() throws {
        let open = try #require(LiveMessage(text: #"{"type":"state","status":"open","contentState":\#(Sample.pausedState)}"#))
        guard case .state(let status, let state) = open else {
            Issue.record("Expected a state, got \(open)")
            return
        }
        #expect(status == "open")
        #expect(state?.v == 4)
        #expect(state?.member(id: "u1Av4Nq8sT")?.state == .paused)
        #expect(!open.isEnded)

        let ended = try #require(LiveMessage(json: Data(#"{"type":"state","status":"ended","contentState":\#(Sample.contentState)}"#.utf8)))
        #expect(ended.isEnded)
        let finalState = try JSONDecoder().decode(LockinAttributes.ContentState.self, from: Data(Sample.contentState.utf8))
        #expect(ended == .state(status: "ended", contentState: finalState))
    }

    @Test func pongsDecodeAndEverythingElseIsSkipped() {
        #expect(LiveMessage(text: #"{"type":"pong"}"#) == .pong)
        #expect(!LiveMessage.pong.isEnded)
        // A type from a newer server, a state without its status, a broken state, and not JSON.
        #expect(LiveMessage(text: #"{"type":"typing","who":"u1"}"#) == nil)
        #expect(LiveMessage(text: #"{"type":"state","contentState":null}"#) == nil)
        #expect(LiveMessage(text: #"{"type":"state","status":"open","contentState":{"v":"one"}}"#) == nil)
        #expect(LiveMessage(text: "pong") == nil)
        // A state the server sends without one still reads.
        #expect(LiveMessage(text: #"{"type":"state","status":"ended","contentState":null}"#) == .state(status: "ended", contentState: nil))
    }

    @Test func framesOfBothKindsAreRead() {
        #expect(APIClient.liveMessage(from: .string(#"{"type":"pong"}"#)) == .pong)
        #expect(APIClient.liveMessage(from: .data(Data(#"{"type":"pong"}"#.utf8))) == .pong)
        #expect(APIClient.liveMessage(from: .string("{}")) == nil)
    }

    @Test func thePingIsTheContractsJSON() throws {
        let object = try #require(JSONSerialization.jsonObject(with: Data(LiveMessage.ping.utf8)) as? [String: String])
        #expect(object == ["type": "ping"])
    }

    @Test func theHandshakeIsAWebSocketWithTheBearerToken() throws {
        let client = APIClient(baseURL: URL(string: "https://api.lockin.test")!, tokens: InMemoryTokenStore(token: "abc123"))
        let request = try client.liveRequest(sessionId: "r7Kq2xP9aL")
        #expect(request.url?.absoluteString == "wss://api.lockin.test/sessions/r7Kq2xP9aL/live")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")

        let local = APIClient(baseURL: URL(string: "http://localhost:8787/api")!, tokens: InMemoryTokenStore(token: "t"))
        #expect(try local.liveRequest(sessionId: "r7Kq2xP9aL").url?.absoluteString == "ws://localhost:8787/api/sessions/r7Kq2xP9aL/live")
    }

    @Test func withoutASessionTheLiveViewFailsAtOnce() async {
        let client = APIClient(baseURL: URL(string: "https://api.lockin.test")!, tokens: InMemoryTokenStore(token: nil))
        await #expect(throws: APIError.server(status: 401, code: .unauthorised, message: nil)) {
            for try await _ in client.liveUpdates(sessionId: "r7Kq2xP9aL") {}
        }
        let unconfigured = APIClient(baseURL: nil, tokens: InMemoryTokenStore(token: "t"))
        await #expect(throws: APIError.notConfigured) {
            for try await _ in unconfigured.liveUpdates(sessionId: "r7Kq2xP9aL") {}
        }
    }

    @Test func howTheLiveViewEnds() throws {
        // The room closes with 1000 once it has ended: no error.
        #expect(APIClient.liveFailure(URLError(.networkConnectionLost), closeCode: .normalClosure, response: nil) == nil)

        // The handshake turned down.
        let url = URL(string: "wss://api.lockin.test/sessions/r7Kq2xP9aL/live")!
        let forbidden = HTTPURLResponse(url: url, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)
        let refused = APIClient.liveFailure(URLError(.badServerResponse), closeCode: .invalid, response: forbidden)
        #expect((refused as? APIError) == .server(status: 403, code: .other("http_403"), message: nil))
        let unauthorised = HTTPURLResponse(url: url, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)
        #expect((APIClient.liveFailure(URLError(.badServerResponse), closeCode: .invalid, response: unauthorised) as? APIError)?.isUnauthorised == true)

        // Dropped, or stopped by the consumer.
        #expect((APIClient.liveFailure(URLError(.notConnectedToInternet), closeCode: .invalid, response: nil) as? APIError) == .offline)
        #expect(APIClient.liveFailure(URLError(.cancelled), closeCode: .goingAway, response: nil) is CancellationError)
    }
}
