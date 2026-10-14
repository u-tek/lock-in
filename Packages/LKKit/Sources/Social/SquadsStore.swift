import API
import Combine
import Core
import Foundation
import Model

/// Your squads: the list, making one, inviting to one, joining one by code, muting and leaving
/// (docs/milestones/M3.md).
///
/// Squads are joined by code, QR or invite link only, like friends (SPEC.md §1.6). Hitting a free
/// limit throws `APIError` with `plusLimit` set ("squads" or "members"): the app opens the paywall
/// for it. Signing out empties the store, when it was given the account.
@MainActor
public final class SquadsStore: ObservableObject {
    /// In the order you joined them, as the server lists them.
    @Published public private(set) var squads: [Squad] = []
    @Published public private(set) var isLoading = false
    /// Why the last refresh or mute didn't work, for a line on the Squads screen. Nil once one
    /// works; the screen may clear it.
    @Published public var problem: String? = nil
    /// The list has loaded at least once since signing in.
    @Published public private(set) var hasLoaded = false

    /// Squads made and invites redeemed: counts only.
    public var analytics: Analytics = .disabled

    private let api: any LockinAPI
    private let account: AccountStore?

    /// - Parameter account: Signing out (or the server turning the session down) empties the
    ///   store. Nil: the store only checks that the API has a session.
    public init(api: any LockinAPI, account: AccountStore? = nil) {
        self.api = api
        self.account = account
        account?.whenSignedOut { [weak self] in
            self?.reset()
        }
    }

    /// Squads with nothing behind them, for snapshots and previews. Its actions answer from
    /// `PreviewAPI`, so they never fail.
    public static func preview(squads: [Squad]) -> SquadsStore {
        let store = SquadsStore(api: PreviewAPI(squads: squads))
        store.squads = squads
        store.hasLoaded = true
        return store
    }

    /// Longest names are 20 characters (`LiveActivityLimits.maxSquadNameLength`), the same rules
    /// as display names otherwise.
    public static let maxNameLength = LiveActivityLimits.maxSquadNameLength

    public func squad(id: String) -> Squad? {
        squads.first { $0.id == id }
    }

    // MARK: - Loading

    /// Fetches the list. Failures land in `problem`.
    public func refresh() async {
        guard canAsk else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await call { try await api.squads() }
            squads = list
            hasLoaded = true
            problem = nil
        } catch {
            note(error)
        }
    }

    // MARK: - Squads

    /// Makes a squad, with you in it. Throws `APIError`: `nameInvalid` / `nameNotAllowed` (checked
    /// here first, so a bad name fails without asking), `plusRequired` with `plusLimit` "squads".
    @discardableResult
    public func create(name: String) async throws -> Squad {
        let trimmed = try Self.checkedName(name)
        let squad = try await call { try await api.createSquad(name: trimmed) }
        upsert(squad)
        analytics.track(.squadCreated)
        return squad
    }

    /// Renames a squad: its owner only (`notOwner` otherwise).
    @discardableResult
    public func rename(_ squad: Squad, to name: String) async throws -> Squad {
        let trimmed = try Self.checkedName(name)
        let renamed = try await call { try await api.renameSquad(id: squad.id, name: trimmed) }
        upsert(renamed)
        return renamed
    }

    /// Your invite code for the squad, with its link: the current one, or a new one once it has
    /// expired (7 days).
    public func invite(_ squad: Squad) async throws -> FriendCode {
        try await call { try await api.squadInvite(id: squad.id) }
    }

    /// Joins the squad whose code this is. Throws `APIError`: `codeNotFound` (also for a code that
    /// can't exist, without asking), `codeExpired`, `alreadyMember`, `blocked`, `friendCode` (it's
    /// a friend's code: `redeemInvite` handles both), `plusRequired` with `plusLimit`.
    @discardableResult
    public func join(code input: String) async throws -> Squad {
        let code = FriendCode.normalised(input)
        guard FriendCode.isWellFormed(code) else {
            throw APIError.server(status: 404, code: .codeNotFound, message: nil)
        }
        let squad = try await call { try await api.joinSquad(code: code) }
        upsert(squad)
        analytics.track(.inviteRedeemed)
        return squad
    }

    /// Mutes or unmutes "X is locking in" for this squad. The switch moves at once and moves back
    /// if the server says no (the reason lands in `problem`).
    public func setMuted(_ squad: Squad, _ muted: Bool) async {
        guard let index = squads.firstIndex(where: { $0.id == squad.id }) else { return }
        let before = squads[index]
        squads[index].muted = muted
        do {
            let saved = try await call { try await api.setSquadMuted(id: squad.id, muted: muted) }
            upsert(saved)
            problem = nil
        } catch {
            if let index = squads.firstIndex(where: { $0.id == squad.id }), squads[index].muted == muted {
                squads[index] = before
            }
            note(error)
        }
    }

    /// Leaves the squad. If you own it, the squad passes to the longest-standing member.
    public func leave(_ squad: Squad) async throws {
        try await call { try await api.leaveSquad(id: squad.id) }
        squads.removeAll { $0.id == squad.id }
    }

    /// The share sheet opened with a squad's invite link.
    public func noteInviteShared() {
        analytics.track(.inviteShared)
    }

    // MARK: - Plumbing

    /// Signed in with a handle (when the store has the account), and the API has a session.
    private var canAsk: Bool {
        guard api.isConfigured, api.hasSession else { return false }
        if let account {
            return account.state.isSignedIn
        }
        return true
    }

    /// A squad from any answer: replaced where it is, or added at the end (the newest joined).
    private func upsert(_ squad: Squad) {
        if let index = squads.firstIndex(where: { $0.id == squad.id }) {
            squads[index] = squad
        } else {
            squads.append(squad)
        }
    }

    private func reset() {
        squads = []
        hasLoaded = false
        problem = nil
    }

    /// A failed refresh or mute: a 401 signs out, anything else shows as `problem`.
    private func note(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        let failure = error as? APIError ?? .invalidResponse
        if failure.isUnauthorised {
            account?.endSession()
            reset()
        } else {
            problem = failure.errorDescription
        }
    }

    /// Runs an API call; a 401 ends the session (and so empties this store) before the error goes
    /// on.
    private func call<Value>(_ request: @MainActor () async throws -> Value) async throws -> Value {
        do {
            return try await request()
        } catch let error as APIError where error.isUnauthorised {
            if let account {
                account.endSession()
            } else {
                reset()
            }
            throw error
        }
    }

    /// A squad name as it's sent: trimmed the way the server trims, and checked against the same
    /// rules first.
    static func checkedName(_ name: String) throws -> String {
        let trimmed = Moderation.trimmed(name)
        switch Moderation.checkName(trimmed, maxLength: maxNameLength) {
        case .ok:
            return trimmed
        case .invalid:
            throw APIError.server(status: 422, code: .nameInvalid, message: nil)
        case .notAllowed:
            throw APIError.server(status: 422, code: .nameNotAllowed, message: nil)
        }
    }
}
