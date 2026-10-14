import Foundation
import Testing
@testable import DeepFocus

@Suite struct SlipInboxTests {
    private func slip(_ session: String, _ at: Double) -> Slip {
        Slip(sessionID: session, at: at)
    }

    @Test func drainsWhatWasAppendedOldestFirst() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let inbox = SlipInbox(storage: storage)
        let first = slip("s1", 1_800_000_000)
        let second = Slip(sessionID: "s1", at: 1_800_000_060.5, appName: "Instagram")
        try inbox.append(first)
        try inbox.append(second)
        #expect(inbox.drain() == [first, second])
        #expect(inbox.drain().isEmpty)
    }

    @Test func drainingNothingCreatesNothing() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        #expect(SlipInbox(storage: storage).drain().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storage.slipsURL.path))
    }

    @Test func pendingLeavesSlipsInPlace() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let inbox = SlipInbox(storage: storage)
        try inbox.append(slip("s1", 1))
        #expect(inbox.pending().count == 1)
        #expect(inbox.pending().count == 1)
        #expect(inbox.drain().count == 1)
        #expect(inbox.pending().isEmpty)
    }

    @Test func slipsThatDidntSendCanGoBack() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let inbox = SlipInbox(storage: storage)
        try inbox.append(slip("s1", 1))
        let drained = inbox.drain()
        try inbox.append(slip("s1", 2))
        try inbox.append(contentsOf: drained)
        try inbox.append(contentsOf: [])
        #expect(inbox.drain().map(\.at) == [2, 1])
    }

    @Test func aLineThatDoesntDecodeIsSkipped() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let inbox = SlipInbox(storage: storage)
        try inbox.append(slip("s1", 1))
        // A write cut short by a crash, with no newline.
        let handle = try FileHandle(forWritingTo: storage.slipsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"x\",\"sessi".utf8))
        try handle.close()
        // The next append starts a fresh line, so only the broken one is lost.
        try inbox.append(slip("s1", 3))
        #expect(inbox.drain().map(\.at) == [1, 3])
    }

    @Test func eachSlipIsOneLineWithUnixSeconds() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        try SlipInbox(storage: storage).append(Slip(id: "a", sessionID: "s1", at: 1_800_000_000.25))
        let text = try String(contentsOf: storage.slipsURL, encoding: .utf8)
        #expect(text.hasSuffix("\n"))
        #expect(text.filter { $0 == "\n" }.count == 1)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["at"] as? Double == 1_800_000_000.25)
        #expect(object["sessionID"] as? String == "s1")
        #expect(object["id"] as? String == "a")
        #expect(object["appName"] == nil)
    }

    /// The app and the shield action extension, standing in as two threads with their own file
    /// handles: nothing lost, nothing interleaved, each writer's slips in its own order.
    @Test func twoWritersLoseNothing() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let url = storage.slipsURL
        let perWriter = 250
        DispatchQueue.concurrentPerform(iterations: 2) { writer in
            let inbox = SlipInbox(url: url)
            for index in 0..<perWriter {
                try? inbox.append(Slip(sessionID: "writer\(writer)", at: Double(index)))
            }
        }
        let drained = SlipInbox(url: url).drain()
        #expect(drained.count == 2 * perWriter)
        #expect(Set(drained.map(\.id)).count == 2 * perWriter)
        for writer in 0..<2 {
            let times = drained.filter { $0.sessionID == "writer\(writer)" }.map(\.at)
            #expect(times == (0..<perWriter).map(Double.init))
        }
    }

    /// Draining while the extension appends: every slip comes out exactly once.
    @Test func drainingWhileAnotherWritesLosesNothing() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let url = storage.slipsURL
        let total = 300
        let writing = DispatchGroup()
        DispatchQueue.global().async(group: writing) {
            let inbox = SlipInbox(url: url)
            for index in 0..<total {
                try? inbox.append(Slip(sessionID: "s1", at: Double(index)))
            }
        }
        var drained: [Slip] = []
        let drainer = SlipInbox(url: url)
        while writing.wait(timeout: .now() + .milliseconds(1)) == .timedOut {
            drained += drainer.drain()
        }
        drained += drainer.drain()
        #expect(drained.count == total)
        #expect(drained.map(\.at) == (0..<total).map(Double.init))
    }
}
