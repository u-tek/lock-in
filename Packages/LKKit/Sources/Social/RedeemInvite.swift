import API
import Foundation

/// What an invite code turned out to be.
public enum InviteTarget: Hashable, Sendable {
    /// A squad code: you're in the squad now.
    case squad(Squad)
    /// A friend code: you're friends now.
    case friend(Friend)
}

/// Redeems a code from a `/j/<code>` link, a QR code or the keyboard, whichever kind it is.
///
/// Squad codes and friend codes look the same, so it tries `POST /squads/join/:code` first; the
/// server answers 422 `friend_code` for a friend's code, which then goes to
/// `POST /friends/redeem/:code` (docs/milestones/M3.md, "As built"). Your own friend code goes
/// straight to the friends store, which turns it down without asking.
///
/// Throws `APIError`, as `SquadsStore.join(code:)` and `FriendsStore.redeem(code:)` do: a code
/// that can't exist fails with `codeNotFound` without a request.
@MainActor
public func redeemInvite(code input: String, squads: SquadsStore, friends: FriendsStore) async throws -> InviteTarget {
    let code = FriendCode.normalised(input)
    guard FriendCode.isWellFormed(code) else {
        throw APIError.server(status: 404, code: .codeNotFound, message: nil)
    }
    if code == friends.code?.code {
        let friend = try await friends.redeem(code: code)
        return .friend(friend)
    }
    do {
        let squad = try await squads.join(code: code)
        return .squad(squad)
    } catch let error as APIError where error.code == .friendCode {
        let friend = try await friends.redeem(code: code)
        return .friend(friend)
    }
}

extension FriendsStore {
    /// Redeems the waiting invite link's code (`pendingInviteCode`), squad or friend, and clears
    /// it. Nil when nothing was waiting. Throws `APIError` as `redeemInvite` does.
    public func redeemPendingInvite(squads: SquadsStore) async throws -> InviteTarget? {
        guard let code = takePendingInvite() else { return nil }
        return try await redeemInvite(code: code, squads: squads, friends: self)
    }
}
