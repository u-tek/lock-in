import Foundation
import Testing
@testable import SessionEngine

@Suite struct SessionStoreTests {
    /// A new, empty directory for one test.
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var sample: StoredSessions {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return StoredSessions(
            memberID: "AbCdE12345",
            avatar: "b3.c7.e2.h4",
            active: ActiveSession(
                id: "Zz00000001",
                startedAt: start,
                endsAt: start.addingTimeInterval(1_500.25),
                pausedAt: start.addingTimeInterval(600.5),
                plannedMinutes: 25,
                version: 4,
                activityID: "activity"
            ),
            history: [record(endingAt: start, minutes: 50)],
            coins: 123,
            completedSessions: 9
        )
    }

    @Test func memoryStoreRoundTrips() {
        let store = SessionStore.inMemory()
        #expect(store.load() == nil)
        store.save(sample)
        #expect(store.load() == sample)
    }

    @Test func memoryStoresAreSeparate() {
        let first = SessionStore.inMemory()
        first.save(sample)
        #expect(SessionStore.inMemory().load() == nil)
    }

    @Test func fileStoreRoundTripsThroughJSON() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/sessions.json")

        let store = SessionStore.file(at: url)
        #expect(store.load() == nil)
        store.save(sample)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(SessionStore.file(at: url).load() == sample)

        var changed = sample
        changed.coins = 124
        store.save(changed)
        #expect(SessionStore.file(at: url).load() == changed)
    }

    @Test func anUnreadableFileIsSetAsideNotOverwritten() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(SessionStore.fileName)
        try Data("{ not json".utf8).write(to: url)

        #expect(SessionStore.file(at: url).load() == nil)
        let aside = directory.appendingPathComponent(SessionStore.unreadableFileName)
        #expect(try Data(contentsOf: aside) == Data("{ not json".utf8))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func missingKeysReadAsDefaults() throws {
        let decoded = try JSONDecoder().decode(StoredSessions.self, from: Data(#"{"coins": 40, "later": true}"#.utf8))
        #expect(decoded.coins == 40)
        #expect(decoded.memberID.count == 10)
        #expect(decoded.avatar == "b0.c0.e0.h0")
        #expect(decoded.active == nil)
        #expect(decoded.history.isEmpty)
        #expect(decoded.completedSessions == 0)
    }

    @Test func historyKeepsTheMostRecentFiveHundred() {
        var stored = StoredSessions()
        let start = Date(timeIntervalSince1970: 0)
        for index in 0..<(SessionStore.historyLimit + 20) {
            stored.append(record(endingAt: start.addingTimeInterval(TimeInterval(index)), minutes: 1))
        }
        #expect(stored.history.count == SessionStore.historyLimit)
        #expect(stored.history.first?.endedAt == start.addingTimeInterval(20))
        #expect(stored.history.last?.endedAt == start.addingTimeInterval(TimeInterval(SessionStore.historyLimit + 19)))
    }

    @Test func activeSessionTiming() {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = ActiveSession(
            id: "x", startedAt: start, endsAt: start.addingTimeInterval(1_500), pausedAt: nil,
            plannedMinutes: 25, version: 1, activityID: nil
        )
        #expect(session.focusedSeconds(at: start.addingTimeInterval(600)) == 600)
        #expect(session.remaining(at: start.addingTimeInterval(600)) == 900)
        // Never below zero or above the plan, whatever the clock says.
        #expect(session.focusedSeconds(at: start.addingTimeInterval(-60)) == 0)
        #expect(session.focusedSeconds(at: start.addingTimeInterval(9_999)) == 1_500)
        #expect(session.remaining(at: start.addingTimeInterval(9_999)) == 0)

        session.pausedAt = start.addingTimeInterval(300)
        #expect(session.focusedSeconds(at: start.addingTimeInterval(9_999)) == 300)
        #expect(session.remaining(at: start.addingTimeInterval(9_999)) == 1_200)
    }
}
