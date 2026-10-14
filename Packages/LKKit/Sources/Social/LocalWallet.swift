import Core
import Foundation
import os

/// What the shop keeps on this phone (docs/milestones/M5.md): coins spent and items bought while
/// signed out, and which accounts this phone's coins have been brought over to. A small JSON file
/// in the App Group, or memory for tests and previews.
///
/// The coins themselves are the session engine's to count (`FocusStats.coins`); this only knows
/// how many of them the shop took, so the balance signed out is the one less the other.
public struct LocalWallet: Sendable {
    public struct Contents: Codable, Equatable, Sendable {
        /// Coins spent in the shop while signed out.
        public var spent: Int
        /// Item ids this phone owns signed out: bought here, or worn when the shop arrived. Oldest
        /// first.
        public var owned: [String]
        /// The accounts (user ids) this phone's coins and items have gone to with
        /// `POST /me/coins/import`, or that said they'd had their import already.
        public var imported: [String]

        public init(spent: Int = 0, owned: [String] = [], imported: [String] = []) {
            self.spent = spent
            self.owned = owned
            self.imported = imported
        }

        /// Lenient, like the session store's file: a missing key reads as its default.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            spent = (try? container.decodeIfPresent(Int.self, forKey: .spent)) ?? 0
            owned = (try? container.decodeIfPresent([String].self, forKey: .owned)) ?? []
            imported = (try? container.decodeIfPresent([String].self, forKey: .imported)) ?? []
        }
    }

    static let fileName = "wallet.json"

    private let backend: Backend

    private init(backend: Backend) {
        self.backend = backend
    }

    /// `wallet.json` beside the session store's file, in the App Group's database directory (or
    /// Application Support without the App Group, as the session store does).
    public static func appGroup() -> LocalWallet {
        let directory: URL
        do {
            directory = try AppGroup.directory(.database)
        } catch {
            Log.app.error("Database directory unavailable; the wallet goes in Application Support")
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppGroup.Directory.database.rawValue, isDirectory: true)
        }
        return file(at: directory.appendingPathComponent(fileName))
    }

    /// Nothing touches the disk. `contents` is what it starts with (nil: nothing saved yet, a
    /// first launch). Copies share the same memory.
    public static func inMemory(_ contents: Contents? = nil) -> LocalWallet {
        let memory = Memory()
        if let contents {
            memory.save(contents)
        }
        return LocalWallet(backend: .memory(memory))
    }

    static func file(at url: URL) -> LocalWallet {
        LocalWallet(backend: .file(FileBackend(url: url)))
    }

    /// What was saved last; nil when nothing was (the first launch with the shop).
    public func load() -> Contents? {
        switch backend {
        case .memory(let memory): memory.load()
        case .file(let file): file.load()
        }
    }

    public func save(_ contents: Contents) {
        switch backend {
        case .memory(let memory): memory.save(contents)
        case .file(let file): file.save(contents)
        }
    }

    private enum Backend: Sendable {
        case memory(Memory)
        case file(FileBackend)
    }

    private final class Memory: Sendable {
        private let contents = OSAllocatedUnfairLock<Contents?>(initialState: nil)

        func load() -> Contents? {
            contents.withLock { $0 }
        }

        func save(_ new: Contents) {
            contents.withLock { $0 = new }
        }
    }

    private final class FileBackend: Sendable {
        let url: URL
        /// The file exists but couldn't be read (the phone hasn't been unlocked since it
        /// restarted): saving now would replace what someone bought with an empty start.
        private let writesBlocked = OSAllocatedUnfairLock(initialState: false)

        init(url: URL) {
            self.url = url
        }

        func load() -> Contents? {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                writesBlocked.withLock { $0 = true }
                Log.app.error("Wallet file exists but couldn't be read; not saving this launch")
                return nil
            }
            do {
                return try JSONDecoder().decode(Contents.self, from: data)
            } catch {
                Log.app.error("Wallet file unreadable; starting fresh")
                return nil
            }
        }

        func save(_ contents: Contents) {
            guard !writesBlocked.withLock({ $0 }) else { return }
            do {
                let data = try JSONEncoder().encode(contents)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Readable while locked, like the session store: the app can start in the
                // background from the Lock Screen.
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                Log.app.error("Couldn't save the wallet")
            }
        }
    }
}
