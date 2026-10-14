import API
import Combine
import Core
import Foundation
import Model

/// Where a username stands while it's being typed.
public enum HandleStatus: Equatable, Sendable {
    case empty
    /// Not 3–20 of `a-z 0-9 _ .` starting with a letter.
    case invalid
    /// Caught by the word lists.
    case notAllowed
    /// Fine as far as this phone can tell; the server is being asked.
    case checking
    case available
    /// Your own handle, unchanged.
    case yours
    case taken
    /// The server couldn't be asked (offline). Saving will ask again, so it doesn't block.
    case unverified

    /// Whether Continue / Save can go ahead with it.
    public var canSave: Bool {
        switch self {
        case .available, .yours, .unverified: true
        case .empty, .invalid, .notAllowed, .checking, .taken: false
        }
    }
}

/// Your Lockin account: signing in with Apple, picking a handle, your profile, signing out and
/// deleting the account, and registering this phone for pushes.
///
/// Accounts are optional (docs/milestones/M2.md): everything solo works signed out. The last
/// account seen is cached, so a signed-in app opens signed in, offline or not; `restore()` then
/// checks the session with the server.
@MainActor
public final class AccountStore: ObservableObject {
    public enum State: Equatable, Sendable {
        case signedOut
        /// Signed in, but no handle yet: the handle picker comes next.
        case needsHandle(User)
        case signedIn(User)

        public init(user: User) {
            self = user.handle == nil ? .needsHandle(user) : .signedIn(user)
        }

        public var user: User? {
            switch self {
            case .signedOut: nil
            case .needsHandle(let user), .signedIn(let user): user
            }
        }

        public var isSignedIn: Bool {
            if case .signedIn = self { true } else { false }
        }
    }

    @Published public private(set) var state: State
    /// A saved session is being checked and there's no cached account to show meanwhile (a
    /// reinstall keeps the Keychain but not the cache).
    @Published public private(set) var isRestoring = false
    /// Apple's given name from this sign-in: the handle picker's first guess at a display name.
    /// Apple shares it on the first sign-in only.
    @Published public private(set) var suggestedName: String?

    /// False when the build has no API host: there's nothing to sign into.
    public let isConfigured: Bool

    private let api: any LockinAPI
    private let cache: UserDefaults?
    private var signedOutActions: [@MainActor () -> Void] = []
    /// This phone's latest registration, kept until there's a session to send it with.
    private var pendingDevice: DeviceRegistration?
    /// What the server has, so an unchanged registration isn't sent again.
    private var sentDevice: DeviceRegistration?
    private var isSendingDevice = false

    static let cacheKey = "LKAccountUser"

    /// - Parameter cache: where the last account seen is kept between launches; nil keeps nothing.
    public init(api: any LockinAPI, cache: UserDefaults? = .standard) {
        self.api = api
        self.cache = cache
        isConfigured = api.isConfigured
        if api.isConfigured, api.hasSession, let user = Self.cachedUser(in: cache) {
            state = State(user: user)
        } else {
            state = .signedOut
        }
    }

    private init(previewState: State, api: any LockinAPI, suggestedName: String?) {
        self.api = api
        cache = nil
        isConfigured = api.isConfigured
        state = previewState
        self.suggestedName = suggestedName
    }

    /// An account that never touches the network or the Keychain, for snapshots and previews.
    public static func preview(_ state: State, isConfigured: Bool = true, suggestedName: String? = nil) -> AccountStore {
        AccountStore(
            previewState: state,
            api: PreviewAPI(isConfigured: isConfigured, user: state.user),
            suggestedName: suggestedName
        )
    }

    public var user: User? {
        state.user
    }

    // MARK: - Session

    /// Checks the saved session with the server. Call at launch. Offline, the cached account
    /// stands; a rejected session signs out.
    public func restore() async {
        guard isConfigured else { return }
        guard api.hasSession else {
            if state != .signedOut {
                endSession()
            }
            return
        }
        isRestoring = state == .signedOut
        defer { isRestoring = false }
        do {
            let user = try await call { try await api.me() }
            // Unless they signed out while it was asked.
            guard api.hasSession else { return }
            apply(user)
            await flushDevice()
        } catch {
            // Offline or a server hiccup: keep what's cached. A 401 has already signed out.
        }
    }

    /// Signs in with what Sign in with Apple returned. Throws `APIError`.
    ///
    /// - Parameter displayName: Apple's given name, when it shared one. Sent only if it would pass
    ///   as a display name; either way the handle picker lets the person change it.
    public func signIn(identityToken: String, authorizationCode: String?, displayName: String?) async throws {
        let name = displayName.map(Moderation.trimmed).flatMap { Moderation.checkName($0) == .ok ? $0 : nil }
        let result = try await api.signInWithApple(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            displayName: name
        )
        suggestedName = result.user.displayName ?? name
        apply(result.user)
        await flushDevice()
    }

    /// Forgets the session on this phone. Friends and history stay on the server.
    public func signOut() {
        api.signOut()
        endSession()
    }

    /// Deletes the account and everything the server holds for it (App Review 5.1.1(v)), then
    /// signs out. Throws `APIError`.
    public func deleteAccount() async throws {
        try await call { try await api.deleteMe() }
        api.signOut()
        endSession()
    }

    // MARK: - Profile

    /// The handle field's verdict without asking the server: everything but `.available`,
    /// `.taken` and `.unverified`. `.checking` means it's worth asking.
    public func localHandleStatus(_ input: String) -> HandleStatus {
        let handle = input.lowercased()
        guard !handle.isEmpty else { return .empty }
        if handle == user?.handle {
            return .yours
        }
        switch Moderation.checkHandle(handle) {
        case .ok: return .checking
        case .invalid: return .invalid
        case .notAllowed: return .notAllowed
        }
    }

    /// The local verdict, then the server's (`GET /handles/:handle`). The view debounces it.
    public func checkHandle(_ input: String) async -> HandleStatus {
        let local = localHandleStatus(input)
        guard local == .checking else { return local }
        do {
            let answer = try await call { try await api.handleAvailability(input.lowercased()) }
            if answer.available {
                return .available
            }
            switch answer.reason {
            case .invalid: return .invalid
            case .notAllowed: return .notAllowed
            case .taken, nil: return .taken
            }
        } catch is CancellationError {
            return .checking
        } catch {
            return .unverified
        }
    }

    /// Saves the handle and display name (and the Lockling, when given), sending only what
    /// changed. Throws `APIError`: `handleTaken`, `handleInvalid`, `handleNotAllowed`,
    /// `nameInvalid`, `nameNotAllowed`, …
    public func setProfile(handle: String, displayName: String, avatar: AvatarCode? = nil) async throws {
        guard let current = user else {
            throw APIError.server(status: 401, code: .unauthorised, message: nil)
        }
        var update = ProfileUpdate()
        let handle = handle.lowercased()
        if handle != current.handle {
            update.handle = handle
        }
        let name = Moderation.trimmed(displayName)
        if name != current.displayName {
            update.displayName = name
        }
        if let avatar, avatar.code != current.avatarCode {
            update.avatarCode = avatar.code
        }
        guard !update.isEmpty else { return }
        let saved = try await call { try await api.updateMe(update) }
        adopt(saved)
    }

    /// Saves your Lockling to the account, so friends see the one on this phone. Does nothing
    /// signed out or when it's already saved; a failure waits for the next change.
    public func updateAvatar(_ avatar: AvatarCode) async {
        guard let current = user, avatar.code != current.avatarCode else { return }
        do {
            let saved = try await call { try await api.updateMe(ProfileUpdate(avatarCode: avatar.code)) }
            adopt(saved)
        } catch {
            Log.api.error("Couldn't save the Lockling to the account")
        }
    }

    // MARK: - Device

    /// Registers this phone for pushes (`POST /devices`): now if signed in, else as soon as the
    /// person signs in. An unchanged registration isn't sent twice.
    public func registerDevice(_ device: DeviceRegistration) async {
        pendingDevice = device
        await flushDevice()
    }

    public func registerDevice(
        token: String,
        env: APNsEnvironment,
        laEnabled: Bool,
        frequentPushes: Bool,
        timeZone: String = TimeZone.current.identifier,
        pushToStartToken: String? = nil
    ) async {
        await registerDevice(DeviceRegistration(
            apnsToken: token,
            env: env,
            pushToStartToken: pushToStartToken,
            laEnabled: laEnabled,
            frequentPushes: frequentPushes,
            tz: timeZone
        ))
    }

    /// Sends the latest registration until the server has it. One at a time: a registration that
    /// arrives mid-send goes next.
    private func flushDevice() async {
        guard !isSendingDevice else { return }
        isSendingDevice = true
        defer { isSendingDevice = false }
        while state != .signedOut, api.hasSession, let device = pendingDevice, device != sentDevice {
            do {
                try await call { try await api.registerDevice(device) }
                sentDevice = device
            } catch {
                // Tried again with the next registration, sign-in or launch.
                Log.push.error("Couldn't register the device with the server")
                return
            }
        }
    }

    // MARK: - Plumbing

    /// Runs `action` when the session ends, whether by signing out, deleting the account or the
    /// server turning the token down. The friends store clears itself this way.
    func whenSignedOut(_ action: @escaping @MainActor () -> Void) {
        signedOutActions.append(action)
    }

    /// The session is gone: show signed out, forget the cache. The token is already cleared (by
    /// `signOut()`, or by the client on a 401).
    func endSession() {
        state = .signedOut
        suggestedName = nil
        sentDevice = nil
        cache?.removeObject(forKey: Self.cacheKey)
        for action in signedOutActions {
            action()
        }
    }

    /// Runs an API call; a 401 ends the session before the error goes on.
    func call<Value>(_ request: () async throws -> Value) async throws -> Value {
        do {
            return try await request()
        } catch let error as APIError where error.isUnauthorised {
            endSession()
            throw error
        }
    }

    /// A user from sign-in: becomes the account.
    private func apply(_ user: User) {
        state = State(user: user)
        save(user)
    }

    /// A user from any other response: only if it's still the signed-in account. A reply that
    /// lands after signing out mustn't sign back in.
    private func adopt(_ user: User) {
        guard state.user?.id == user.id else { return }
        apply(user)
    }

    private func save(_ user: User) {
        guard let cache, let data = try? JSONEncoder().encode(user) else { return }
        cache.set(data, forKey: Self.cacheKey)
    }

    private static func cachedUser(in cache: UserDefaults?) -> User? {
        guard let data = cache?.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }
}
