import API
import Combine
import Core
import Foundation
import Model

/// Your friends, your friend code, and the people you've blocked.
///
/// Friends are added by code, QR or invite link only (SPEC.md §1.6): no contacts, no search.
/// Everything here needs a signed-in account with a handle; signing out empties it.
@MainActor
public final class FriendsStore: ObservableObject {
    /// Sorted by name.
    @Published public private(set) var friends: [Friend] = []
    /// Your current code. Nil until the first refresh.
    @Published public private(set) var code: FriendCode? = nil
    /// Sorted by name. Loaded by `refreshBlocked()`.
    @Published public private(set) var blocked: [Friend] = []
    /// The friends list has loaded at least once since signing in.
    @Published public private(set) var hasLoaded = false
    @Published public private(set) var isLoading = false
    /// Why the last refresh failed; nil once one works.
    @Published public private(set) var problem: APIError? = nil
    /// An invite link's code, waiting for the Friends screen (and, before that, maybe for
    /// signing in). It may be a squad's code as well as a friend's: redeem it with
    /// `redeemPendingInvite(squads:)` (or `takePendingInvite()` and `redeemInvite`), which tells
    /// them apart.
    @Published public private(set) var pendingInviteCode: String? = nil

    /// Invites shared and redeemed: counts only.
    public var analytics: Analytics = .disabled

    private let api: any LockinAPI
    private let account: AccountStore

    public init(api: any LockinAPI, account: AccountStore) {
        self.api = api
        self.account = account
        account.whenSignedOut { [weak self] in
            self?.reset()
        }
    }

    /// Friends with nothing behind them, for snapshots and previews.
    public static func preview(
        account: AccountStore,
        friends: [Friend] = [],
        code: FriendCode? = PreviewAPI.sampleCode,
        blocked: [Friend] = [],
        redeems: Friend? = nil
    ) -> FriendsStore {
        let api = PreviewAPI(
            friends: friends,
            code: code ?? PreviewAPI.sampleCode,
            blocked: blocked,
            redeems: redeems ?? friends.first ?? PreviewAPI.sampleFriend
        )
        let store = FriendsStore(api: api, account: account)
        store.analytics = .disabled
        store.friends = Self.sorted(friends)
        store.code = code
        store.blocked = Self.sorted(blocked)
        store.hasLoaded = true
        return store
    }

    // MARK: - Loading

    /// Fetches the friends list and your code together. Failures land in `problem`.
    public func refresh() async {
        guard account.state.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        let api = self.api
        do {
            async let list = api.friends()
            async let current = api.friendCode()
            let (friends, code) = try await (list, current)
            self.friends = Self.sorted(friends)
            self.code = code
            hasLoaded = true
            problem = nil
        } catch {
            note(error)
        }
    }

    /// Fetches the people you've blocked.
    public func refreshBlocked() async {
        guard account.state.isSignedIn else { return }
        do {
            let list = try await api.blocked()
            blocked = Self.sorted(list)
        } catch {
            note(error)
        }
    }

    // MARK: - Friends

    /// Adds the friend whose code this is. Throws `APIError` (`codeNotFound`, `codeExpired`,
    /// `ownCode`, `alreadyFriends`, `blocked`, …); a code that can't exist fails without asking.
    /// A squad's code answers `codeNotFound` here: for a code that could be either (an invite
    /// link, a scanned QR code), use `redeemInvite(code:squads:friends:)`.
    @discardableResult
    public func redeem(code input: String) async throws -> Friend {
        let code = FriendCode.normalised(input)
        guard FriendCode.isWellFormed(code) else {
            throw APIError.server(status: 404, code: .codeNotFound, message: nil)
        }
        guard code != self.code?.code else {
            throw APIError.server(status: 422, code: .ownCode, message: nil)
        }
        let friend = try await call { try await api.redeemFriendCode(code) }
        insert(friend)
        analytics.track(.inviteRedeemed)
        return friend
    }

    /// Ends a friendship. The row goes at once and comes back if the server says no.
    public func remove(_ friend: Friend) async throws {
        guard friends.contains(where: { $0.id == friend.id }) else { return }
        friends.removeAll { $0.id == friend.id }
        do {
            try await call { try await api.removeFriend(id: friend.id) }
        } catch {
            if account.state.isSignedIn {
                insert(friend)
            }
            throw error
        }
    }

    /// Blocks someone: it ends the friendship, and they can't add you again.
    public func block(_ person: Friend) async throws {
        try await call { try await api.block(userId: person.id) }
        friends.removeAll { $0.id == person.id }
        if !blocked.contains(where: { $0.id == person.id }) {
            var entry = person
            entry.since = UnixTime.seconds(Date())
            blocked = Self.sorted(blocked + [entry])
        }
    }

    public func unblock(_ person: Friend) async throws {
        try await call { try await api.unblock(userId: person.id) }
        blocked.removeAll { $0.id == person.id }
    }

    /// Reports someone to the Lockin team (SPEC.md §7). Reporting doesn't block; that's separate.
    public func report(userId: String, reason: ReportReason, note: String? = nil) async throws {
        try await call { try await api.report(userId: userId, reason: reason, note: note) }
    }

    // MARK: - Invites

    /// The share sheet opened with the invite link.
    public func noteInviteShared() {
        analytics.track(.inviteShared)
    }

    /// An invite link was opened: the code waits for the Friends screen.
    public func openInvite(_ link: InviteLink) {
        pendingInviteCode = link.code
    }

    /// The waiting invite's code, once: the Friends screen redeems it.
    public func takePendingInvite() -> String? {
        defer { pendingInviteCode = nil }
        return pendingInviteCode
    }

    // MARK: - Plumbing

    private func insert(_ friend: Friend) {
        friends = Self.sorted(friends.filter { $0.id != friend.id } + [friend])
    }

    private func reset() {
        friends = []
        code = nil
        blocked = []
        hasLoaded = false
        problem = nil
    }

    /// A failed refresh: a 401 signs out, anything else shows as `problem`.
    private func note(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        let failure = error as? APIError ?? .invalidResponse
        if failure.isUnauthorised {
            account.endSession()
        } else {
            problem = failure
        }
    }

    /// Runs an API call; a 401 ends the session (and so empties this store) before the error goes
    /// on.
    private func call<Value>(_ request: @MainActor () async throws -> Value) async throws -> Value {
        do {
            return try await request()
        } catch let error as APIError where error.isUnauthorised {
            account.endSession()
            throw error
        }
    }

    static func sorted(_ people: [Friend]) -> [Friend] {
        people.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }
}
