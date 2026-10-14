import Foundation
import Model
import Testing
@testable import SessionEngine

@Suite struct RoomLinkStoreTests {
    private var squadSample: StoredSessions {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let attributes = LockinAttributes(sid: "RmGoblins1", me: "uAva000001", sq: "Library Goblins")
        let member = LockinAttributes.ContentState.Member(
            id: "uAva000001", name: "Ava", state: .paused,
            start: start, end: start.addingTimeInterval(1_500), pausedAt: start.addingTimeInterval(600)
        )
        return StoredSessions(
            memberID: "AbCdE12345",
            active: ActiveSession(
                id: "Zz00000001",
                startedAt: start,
                endsAt: start.addingTimeInterval(1_500),
                pausedAt: start.addingTimeInterval(600),
                plannedMinutes: 25,
                version: 3,
                activityID: nil,
                sessionId: "RmGoblins1"
            ),
            coins: 12,
            room: RoomLink(
                squadId: "SqGoblins1",
                attributes: attributes,
                state: LockinAttributes.ContentState(v: 3, m: [member]),
                activityID: "activity"
            ),
            pendingEnd: "RmOld00001"
        )
    }

    @Test func aSquadSessionRoundTrips() throws {
        let store = SessionStore.inMemory()
        store.save(squadSample)
        let loaded = try #require(store.load())
        #expect(loaded == squadSample)
        #expect(loaded.active?.isSquad == true)
        #expect(loaded.room?.sessionId == "RmGoblins1")
        #expect(loaded.room?.me == "uAva000001")
        #expect(loaded.room?.mine?.state == .paused)
    }

    @Test func aFileFromBeforeSquadsReadsAsSolo() throws {
        let json = #"{"coins": 40, "active": {"id": "Zz00000001", "startedAt": 0, "endsAt": 1500, "plannedMinutes": 25, "version": 1}}"#
        let decoded = try JSONDecoder().decode(StoredSessions.self, from: Data(json.utf8))
        #expect(decoded.active?.sessionId == nil)
        #expect(decoded.active?.isSquad == false)
        #expect(decoded.room == nil)
        #expect(decoded.pendingEnd == nil)
    }

    @Test func aRoomThisVersionCannotReadCostsNothingElse() throws {
        let json = #"{"coins": 40, "room": {"squadId": 7}, "pendingEnd": "RmOld00001"}"#
        let decoded = try JSONDecoder().decode(StoredSessions.self, from: Data(json.utf8))
        #expect(decoded.coins == 40)
        #expect(decoded.room == nil)
        #expect(decoded.pendingEnd == "RmOld00001")
    }
}
