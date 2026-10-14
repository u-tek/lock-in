import Core
import Foundation

/// The directory the app and the Deep Focus extensions share: `DeepFocus/` in the App Group.
///
/// - `selection.json`: the apps, categories and websites to shield (`DeepFocusSelection`).
/// - `state.json`: the session being shielded and the apps on a grace (`DeepFocusEngine`).
/// - `state.lock`: taken while any process changes the state and the shields to match.
/// - `slips.jsonl`: "Open anyway" taps waiting for the app (`SlipInbox`).
public struct DeepFocusStorage: Sendable, Equatable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group's DeepFocus directory. Without the App Group (an unsigned simulator build)
    /// each process gets its own, as `AppGroup.containerURL` explains.
    public static func appGroup(configuration: AppConfiguration = .main) -> DeepFocusStorage {
        DeepFocusStorage(
            directory: AppGroup.containerURL(configuration: configuration)
                .appendingPathComponent(directoryName, isDirectory: true)
        )
    }

    static let directoryName = "DeepFocus"

    var selectionURL: URL { directory.appendingPathComponent("selection.json") }
    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var stateLockURL: URL { directory.appendingPathComponent("state.lock") }
    var slipsURL: URL { directory.appendingPathComponent("slips.jsonl") }

    /// Creates the directory if needed.
    ///
    /// Kept out of backups: the state describes a session on this phone, and restored onto another
    /// it would shield apps for a session that isn't running there.
    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }
}

/// Small files that the app and its extensions read and write, sometimes at the same moment.
enum SharedFile {
    /// How long to wait for another process to let go of a lock before going ahead without it.
    /// An extension that hangs gets killed, which loses more than a rare race would.
    static let lockTimeout: TimeInterval = 1

    /// Opens (creating) the file at `url`, takes an exclusive `flock` on it, and runs `body` with
    /// the open file. The lock is held only for `body`: a process suspended while holding a lock in
    /// the App Group container is killed by the system.
    ///
    /// `flock` locks belong to the open file, so two openings contend even within one process,
    /// which is what lets the tests stand in for two processes with two threads.
    ///
    /// - Parameter appending: Open with `O_APPEND`, so every write lands at the end even if the
    ///   lock had to be given up on.
    static func withLock<T>(
        _ url: URL,
        appending: Bool = false,
        timeout: TimeInterval = lockTimeout,
        _ body: (FileHandle) throws -> T
    ) throws -> T {
        let flags = O_RDWR | O_CREAT | O_CLOEXEC | (appending ? O_APPEND : 0)
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, flags, 0o644)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        let locked = lock(descriptor, timeout: timeout)
        if !locked {
            deepFocusLog.error("Shared file still locked after \(timeout, privacy: .public) s; going ahead")
        }
        defer {
            if locked {
                flock(descriptor, LOCK_UN)
            }
        }
        return try body(FileHandle(fileDescriptor: descriptor, closeOnDealloc: false))
    }

    private static func lock(_ descriptor: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return true
            }
            let failure = errno
            guard failure == EWOULDBLOCK || failure == EINTR, Date() < deadline else { return false }
            usleep(2_000)
        }
    }

    /// The decoded file, or nil when it's missing or unreadable.
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            deepFocusLog.error("Couldn't decode \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    /// Writes JSON to a temporary file and renames it into place, so a reader in another process
    /// sees the old file or the new one, never half of one.
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}
