import Core
import Foundation
import Security

/// Where the API session token lives between launches.
///
/// Failures are logged rather than thrown: a token that can't be saved still works for this
/// launch, and the worst case is signing in again next time.
public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func clear()
}

/// The session token in the Keychain (SPEC.md §5.5): a generic password under
/// `<bundle id>.session`, readable after the first unlock so a background push can use it, and
/// never copied to another device (a restored backup signs in again).
///
/// Read once, then served from memory: the token changes only through this store.
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    public let service: String
    public let account: String

    // Guards `cached` and `hasRead`; the Keychain is thread-safe on its own.
    private let lock = NSLock()
    private var cached: String?
    private var hasRead = false

    public init(service: String = KeychainTokenStore.defaultService, account: String = "token") {
        self.service = service
        self.account = account
    }

    public static var defaultService: String {
        "\(Bundle.main.bundleIdentifier ?? "Lockin").session"
    }

    public func load() -> String? {
        lock.withLock {
            if !hasRead {
                cached = readKeychain()
                hasRead = true
            }
            return cached
        }
    }

    public func save(_ token: String) {
        lock.withLock {
            cached = token
            hasRead = true
            writeKeychain(Data(token.utf8))
        }
    }

    public func clear() {
        lock.withLock {
            cached = nil
            hasRead = true
            let status = SecItemDelete(baseQuery as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                Log.api.error("Couldn't delete the session token: OSStatus \(status, privacy: .public)")
            }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            Log.api.error("Couldn't read the session token: OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    private func writeKeychain(_ data: Data) {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.api.error("Couldn't save the session token: OSStatus \(status, privacy: .public)")
        }
    }
}

/// A token store that forgets everything when the app quits: tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func load() -> String? {
        lock.withLock { token }
    }

    public func save(_ token: String) {
        lock.withLock { self.token = token }
    }

    public func clear() {
        lock.withLock { token = nil }
    }
}
