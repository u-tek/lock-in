import Foundation

/// One "Open anyway": the person opened a blocked app during a session.
///
/// The squad sees it (member state 5, slipped) and the pet's mood dips, once the app has sent it
/// with `POST /sessions/:id/slip`.
public struct Slip: Codable, Equatable, Sendable, Identifiable {
    /// Unique per tap, so the app can tell slips apart while sending them.
    public var id: String
    /// The session it happened in (`DeepFocusController.start(sessionEnds:sessionID:)`).
    public var sessionID: String
    /// When, in Unix seconds.
    public var at: Double
    /// The app's name, when the process that recorded the slip knew it. The shield action
    /// extension is only given a token, so today it's always nil. On-device only: which apps
    /// someone blocks is never sent to the server.
    public var appName: String?

    public init(id: String = UUID().uuidString, sessionID: String, at: Double, appName: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.at = at
        self.appName = appName
    }

    public var date: Date {
        Date(timeIntervalSince1970: at)
    }
}

/// Slips waiting for the app, in the App Group.
///
/// The shield action extension appends; the app drains. The extensions are assumed to have no
/// network (SPEC.md §9.3), so the app sends what it drains next time it runs.
///
/// One JSON object per line. Every append and drain holds an exclusive `flock` on the file, so two
/// writers never interleave and a drain never drops a slip appended while it ran: a writer either
/// finishes before the drain reads, or waits and appends to the emptied file. A line that doesn't
/// decode (a write cut short by a crash) is skipped.
public struct SlipInbox: Sendable {
    let url: URL
    private let storage: DeepFocusStorage?

    public init(storage: DeepFocusStorage = .appGroup()) {
        self.storage = storage
        self.url = storage.slipsURL
    }

    init(url: URL) {
        self.storage = nil
        self.url = url
    }

    /// Adds a slip at the end. Throws when the App Group can't be written.
    public func append(_ slip: Slip) throws {
        try append(contentsOf: [slip])
    }

    /// Adds slips in one write: what the app puts back when sending them failed.
    public func append(contentsOf slips: [Slip]) throws {
        guard !slips.isEmpty else { return }
        try prepare()
        let encoder = JSONEncoder()
        var lines = Data()
        for slip in slips {
            lines.append(try encoder.encode(slip))
            lines.append(0x0A)
        }
        try SharedFile.withLock(url, appending: true) { file in
            var write = lines
            // A write cut short (a crash mid-append) leaves a line with no end; start a new one so
            // only that line is lost, not this one too.
            let end = try file.seekToEnd()
            if end > 0 {
                try file.seek(toOffset: end - 1)
                if try file.read(upToCount: 1) != Data([0x0A]) {
                    write.insert(0x0A, at: write.startIndex)
                }
                try file.seekToEnd()
            }
            try file.write(contentsOf: write)
        }
    }

    /// Takes every slip out, oldest first. Empty when there are none, or when the file can't be
    /// read right now; then they stay for next time.
    public func drain() -> [Slip] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try SharedFile.withLock(url) { file in
                try file.seek(toOffset: 0)
                let data = try file.readToEnd() ?? Data()
                guard !data.isEmpty else { return [] }
                try file.truncate(atOffset: 0)
                return Self.decode(data)
            }
        } catch {
            deepFocusLog.error("Couldn't drain the slip inbox")
            return []
        }
    }

    /// The slips waiting, without taking them out.
    public func pending() -> [Slip] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return Self.decode(data)
    }

    static func decode(_ data: Data) -> [Slip] {
        let decoder = JSONDecoder()
        var slips: [Slip] = []
        var skipped = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let slip = try? decoder.decode(Slip.self, from: Data(line)) {
                slips.append(slip)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            deepFocusLog.error("Skipped \(skipped, privacy: .public) unreadable slip lines")
        }
        return slips
    }

    private func prepare() throws {
        if let storage {
            try storage.prepare()
        } else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
    }
}
