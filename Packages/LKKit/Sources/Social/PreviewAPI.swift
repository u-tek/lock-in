import API
import Core
import Foundation
import Model

/// A Lockin API made of fixed answers: what the preview stores run on, so snapshots show the real
/// screens without a network, a Keychain or a server.
public struct PreviewAPI: LockinAPI {
    public var isConfigured: Bool
    public var user: User?
    public var friendsList: [Friend]
    public var code: FriendCode
    public var blockedList: [Friend]
    /// Who any code turns out to belong to.
    public var redeems: Friend
    /// Your squads (M3).
    public var squadsList: [Squad]
    /// Each squad's week, by squad id (M5). A squad without one has everyone on 0.
    public var leaderboards: [String: Leaderboard]
    /// What the account owns beyond the defaults (M5).
    public var owned: [String]

    public init(
        isConfigured: Bool = true,
        user: User? = PreviewAPI.sampleUser,
        friends: [Friend] = [],
        code: FriendCode = PreviewAPI.sampleCode,
        blocked: [Friend] = [],
        redeems: Friend = PreviewAPI.sampleFriend,
        squads: [Squad] = [],
        leaderboards: [String: Leaderboard] = [:],
        owned: [String] = []
    ) {
        self.isConfigured = isConfigured
        self.user = user
        friendsList = friends
        self.code = code
        blockedList = blocked
        self.redeems = redeems
        squadsList = squads
        self.leaderboards = leaderboards
        self.owned = owned
    }

    public static let sampleUser = User(
        id: "uPreview01",
        handle: "you",
        displayName: "You",
        avatarCode: "b0.c2.e1.h1",
        coins: 120,
        createdAt: 1_791_900_000
    )

    public static let sampleCode = FriendCode(
        code: "KQ7M2XPA",
        url: URL(string: "https://lockin.example/j/KQ7M2XPA")!,
        expiresAt: 1_792_500_000
    )

    public static let sampleFriend = Friend(
        id: "uPreview02",
        handle: "ava",
        displayName: "Ava",
        avatarCode: "b1.c1.e1.h1",
        since: 1_791_900_000
    )

    /// A squad of four, owned by the sample user, with nobody locked in: its sprout is a teen, it's
    /// focused six days running and today counts.
    public static let sampleSquad = Squad(
        id: "sqPreview1",
        name: "Library Goblins",
        ownerId: sampleUser.id,
        members: [
            SquadMember(id: sampleUser.id, handle: "you", displayName: "You", avatarCode: "b0.c2.e1.h1", joinedAt: 1_791_900_000),
            SquadMember(id: "uPreview02", handle: "ava", displayName: "Ava", avatarCode: "b1.c1.e1.h1", joinedAt: 1_791_900_100),
            SquadMember(id: "uPreview03", handle: "noor.k", displayName: "Noor", avatarCode: "b2.c4.e2.h0", joinedAt: 1_791_900_200),
            SquadMember(id: "uPreview04", handle: "kai", displayName: nil, avatarCode: "b3.c7.e3.h2", joinedAt: 1_791_900_300),
        ],
        openSessionId: nil,
        muted: false,
        pet: SquadPet(species: "sprout", stage: 2, xp: 1_450, mood: PetMood.happy.rawValue),
        streak: SquadStreak(count: 6, countedToday: true, doneToday: 2, needed: 2),
        tz: "Europe/London"
    )

    /// The sample squad's week: Noor ahead, Kai yet to start.
    public static let sampleLeaderboard = Leaderboard(
        weekStart: "2026-10-12",
        startsAt: 1_791_759_600,
        endsAt: 1_792_364_400,
        entries: [
            Leaderboard.Entry(userId: "uPreview03", minutes: 310, sessions: 8),
            Leaderboard.Entry(userId: sampleUser.id, minutes: 245, sessions: 7),
            Leaderboard.Entry(userId: "uPreview02", minutes: 180, sessions: 5),
            Leaderboard.Entry(userId: "uPreview04", minutes: 0, sessions: 0),
        ]
    )

    /// A second squad, someone else's, with a session open right now and its pet hatched.
    public static let sampleLiveSquad = Squad(
        id: "sqPreview2",
        name: "Night Owls",
        ownerId: "uPreview03",
        members: [
            SquadMember(id: "uPreview03", handle: "noor.k", displayName: "Noor", avatarCode: "b2.c4.e2.h0", joinedAt: 1_791_800_000),
            SquadMember(id: sampleUser.id, handle: "you", displayName: "You", avatarCode: "b0.c2.e1.h1", joinedAt: 1_791_850_000),
        ],
        openSessionId: "rmPreview1",
        muted: true,
        pet: SquadPet(species: "puff", stage: 1, xp: 240, mood: PetMood.content.rawValue),
        streak: SquadStreak(count: 2, countedToday: false, doneToday: 0, needed: 1),
        tz: "Europe/London"
    )

    public var hasSession: Bool {
        true
    }

    public func signOut() {}

    public func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async throws -> SignInResult {
        var fresh = user ?? Self.sampleUser
        fresh.handle = nil
        fresh.displayName = displayName
        return SignInResult(user: fresh, isNew: true)
    }

    public func me() async throws -> User {
        user ?? Self.sampleUser
    }

    public func updateMe(_ update: ProfileUpdate) async throws -> User {
        var updated = user ?? Self.sampleUser
        if let handle = update.handle {
            updated.handle = handle
        }
        if let displayName = update.displayName {
            updated.displayName = displayName
        }
        if let avatarCode = update.avatarCode {
            updated.avatarCode = avatarCode
        }
        return updated
    }

    public func handleAvailability(_ handle: String) async throws -> HandleAvailability {
        HandleAvailability(available: true)
    }

    public func deleteMe() async throws {}

    public func registerDevice(_ device: DeviceRegistration) async throws {}

    public func friends() async throws -> [Friend] {
        friendsList
    }

    public func friendCode() async throws -> FriendCode {
        code
    }

    public func redeemFriendCode(_ code: String) async throws -> Friend {
        redeems
    }

    public func removeFriend(id: String) async throws {}

    public func blocked() async throws -> [Friend] {
        blockedList
    }

    public func block(userId: String) async throws {}

    public func unblock(userId: String) async throws {}

    public func report(userId: String, reason: ReportReason, note: String?) async throws {}

    public func signOutSession() async throws {}

    // MARK: - Squads

    public func squads() async throws -> [Squad] {
        squadsList
    }

    public func createSquad(name: String, tz: String?) async throws -> Squad {
        Squad(
            id: "sqPreview9",
            name: name,
            ownerId: (user ?? Self.sampleUser).id,
            members: [Self.member(user ?? Self.sampleUser)],
            pet: SquadPet(species: "ember", stage: 0, xp: 0, mood: PetMood.hungry.rawValue),
            tz: tz
        )
    }

    public func renameSquad(id: String, name: String) async throws -> Squad {
        var squad = squadsList.first { $0.id == id } ?? Self.sampleSquad
        squad.name = name
        return squad
    }

    public func squadInvite(id: String) async throws -> FriendCode {
        code
    }

    public func joinSquad(code: String) async throws -> Squad {
        var squad = Self.sampleLiveSquad
        let me = user ?? Self.sampleUser
        if !squad.members.contains(where: { $0.id == me.id }) {
            squad.members.append(Self.member(me))
        }
        return squad
    }

    public func setSquadMuted(id: String, muted: Bool) async throws -> Squad {
        var squad = squadsList.first { $0.id == id } ?? Self.sampleSquad
        squad.muted = muted
        return squad
    }

    public func leaveSquad(id: String) async throws {}

    public func squadLeaderboard(id: String, week: String?) async throws -> Leaderboard {
        if let board = leaderboards[id] {
            return board
        }
        let members = squadsList.first { $0.id == id }?.members ?? []
        return Leaderboard(
            weekStart: Self.sampleLeaderboard.weekStart,
            startsAt: Self.sampleLeaderboard.startsAt,
            endsAt: Self.sampleLeaderboard.endsAt,
            entries: members.map { Leaderboard.Entry(userId: $0.id, minutes: 0, sessions: 0) }
        )
    }

    /// The server's rules (M7): any accessory while boosted, taking it off whenever.
    public func setPetAccessory(squadId: String, accessory: Int?) async throws -> Squad {
        var squad = squadsList.first { $0.id == squadId } ?? Self.sampleSquad
        if accessory != nil, !squad.boosted {
            throw APIError.server(status: 402, code: .plusRequired, message: nil, details: APIErrorDetails(limit: "boost"))
        }
        squad.pet.accessory = accessory
        return squad
    }

    /// Demo Buddy's session, open now.
    public func askDemoBuddy(squadId: String) async throws -> SessionInfo {
        SessionInfo(id: "rmPreviewDB", squadId: squadId, hostId: "DemoBuddy0", status: SessionInfo.open, createdAt: 1_791_900_000)
    }

    // MARK: - Lockin Plus

    public func refreshPlus() async throws -> User {
        user ?? Self.sampleUser
    }

    // MARK: - Coins and the shop

    public func shop() async throws -> [ShopItem] {
        ShopCatalogue.items
    }

    /// Pays from the sample account's coins. Nothing is kept: the next answer starts over.
    public func buy(itemId: String) async throws -> (coins: Int, owned: [String]) {
        guard let item = ShopCatalogue.item(id: itemId) else {
            throw APIError.server(status: 404, code: .itemNotFound, message: nil)
        }
        let coins = (user ?? Self.sampleUser).coins
        guard !item.plus else { throw APIError.server(status: 402, code: .plusRequired, message: nil) }
        guard coins >= item.price else { throw APIError.server(status: 402, code: .notEnoughCoins, message: nil) }
        return (coins - item.price, owned + [itemId])
    }

    public func cosmetics() async throws -> [String] {
        owned
    }

    public func importCoins(coins: Int, owned: [String]) async throws -> (user: User, owned: [String]) {
        (user ?? Self.sampleUser, self.owned)
    }

    // MARK: - Sessions

    /// Previews never run a squad session: the engine's own previews show one.
    public func startSession(squadId: String?, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession {
        throw APIError.notConfigured
    }

    public func joinSession(id: String, minutes: Int, pushToStart: PushToStart?) async throws -> JoinedSession {
        throw APIError.notConfigured
    }

    public func uploadLiveActivityToken(sessionId: String, token: String, env: APNsEnvironment) async throws {}

    public func pauseSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    public func resumeSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    public func endSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    public func slipSession(id: String) async throws -> LockinAttributes.ContentState {
        throw APIError.notConfigured
    }

    public func cheer(sessionId: String, to memberId: String, kind: Int) async throws {}

    public func session(id: String) async throws -> (session: SessionInfo, contentState: LockinAttributes.ContentState?) {
        throw APIError.notConfigured
    }

    public func liveUpdates(sessionId: String) -> AsyncThrowingStream<LiveMessage, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    private static func member(_ user: User) -> SquadMember {
        SquadMember(id: user.id, handle: user.handle, displayName: user.displayName, avatarCode: user.avatarCode, joinedAt: user.createdAt)
    }
}
