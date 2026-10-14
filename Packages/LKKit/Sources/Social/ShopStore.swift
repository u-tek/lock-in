import API
import Core
import Foundation
import Model

/// Coins and the Lockling items you own, and the coin shop (docs/milestones/M5.md).
///
/// Signed in, the server is the authority: the balance is the account's (`GET /me`), what you own
/// is `GET /me/cosmetics`, and buying goes through `POST /shop/buy`. Signed out, everything stays on
/// this phone: the balance is the session engine's count (`localEarned`, which the app keeps
/// current) less what the shop took, and purchases are kept in a `LocalWallet`.
///
/// The first time an account is signed in on this phone, the phone's coins and items go to it
/// (`POST /me/coins/import`), once: a 409 `already_imported` counts as done. The local wallet is
/// left as it was, for whenever the phone is signed out again.
///
/// Defaults (option 0) are always yours and aren't items. Plus items are the paywall's business
/// (`PlusStore` on the phone); the server counts them as owned while the account has Plus.
@MainActor
public final class ShopStore: ObservableObject {
    /// Coins counted on this phone: the session engine's `FocusStats.coins`. The app keeps it
    /// current.
    @Published public var localEarned: Int
    /// What the shop left on this phone: spent coins, items, and accounts imported to.
    @Published public private(set) var wallet: LocalWallet.Contents
    /// What the server says you own, while signed in; nil until it has said since signing in.
    @Published public private(set) var serverOwned: [String]?
    /// The item being bought from the server, while it is.
    @Published public private(set) var buying: String?

    private let api: any LockinAPI
    private let account: AccountStore
    private let storage: LocalWallet
    /// The coin import in flight, so two callers wait for one.
    private var importTask: Task<Void, Never>?

    /// - Parameters:
    ///   - wallet: where signed-out purchases are kept.
    ///   - avatar: the Lockling on this phone. The first time the shop sees a phone (no wallet
    ///     saved yet), the free parts it's wearing become yours: every part was free before the
    ///     shop, and nobody should lose what they're wearing to it.
    ///   - localEarned: the session engine's coins, until the app keeps it current.
    public init(
        api: any LockinAPI,
        account: AccountStore,
        wallet storage: LocalWallet,
        wearing avatar: AvatarCode = .default,
        localEarned: Int = 0
    ) {
        self.api = api
        self.account = account
        self.storage = storage
        self.localEarned = localEarned
        if let saved = storage.load() {
            wallet = saved
        } else {
            let first = LocalWallet.Contents(owned: ShopCatalogue.freeItemIDs(wornBy: avatar))
            storage.save(first)
            wallet = first
        }
        account.whenSignedOut { [weak self] in
            self?.serverOwned = nil
            self?.buying = nil
        }
    }

    /// A shop with nothing behind it, for snapshots and previews: `coins` to spend (the account's
    /// when `account` is signed in, else this phone's) and `owned` already yours.
    public static func preview(account: AccountStore, coins: Int, owned: [String] = []) -> ShopStore {
        let api = PreviewAPI(user: account.user, owned: owned)
        let store = ShopStore(
            api: api,
            account: account,
            wallet: .inMemory(LocalWallet.Contents(owned: owned)),
            localEarned: coins
        )
        if store.isSignedIn {
            store.serverOwned = owned
        }
        return store
    }

    /// Everything for sale, in the server's order.
    public var items: [ShopItem] {
        ShopCatalogue.items
    }

    /// Signed in with a handle and a session: the server's coins and items count.
    public var isSignedIn: Bool {
        api.isConfigured && api.hasSession && account.state.isSignedIn
    }

    /// Coins to spend: the account's signed in, this phone's otherwise.
    public var coins: Int {
        isSignedIn ? max(0, account.user?.coins ?? 0) : localCoins
    }

    /// This phone's coins: what the session engine counted, less what the shop took here.
    public var localCoins: Int {
        max(0, localEarned - wallet.spent)
    }

    /// Item ids you own beyond the defaults: the server's list signed in (this phone's until it
    /// has answered), this phone's otherwise.
    public var owned: Set<String> {
        if isSignedIn, let serverOwned {
            return Set(serverOwned)
        }
        return Set(wallet.owned)
    }

    public func owns(_ item: ShopItem) -> Bool {
        owned.contains(item.id)
    }

    /// A part's option is yours: the default always is.
    public func owns(part: ShopPart, option: Int) -> Bool {
        option == 0 || owned.contains(ShopItem.id(part: part, option: option))
    }

    /// Coins still to earn before `item` can be bought; 0 when it can.
    public func shortfall(for item: ShopItem) -> Int {
        max(0, item.price - coins)
    }

    // MARK: - Loading

    /// Brings the balance and what you own up to date from the server: after signing in, after a
    /// session (the server credits its coins), when the shop opens. Imports this phone's coins
    /// first, once per account. Signed out it does nothing; offline, what's cached stands.
    public func refresh() async {
        guard isSignedIn else { return }
        await importIfNeeded()
        guard isSignedIn else { return }
        do {
            let user = try await call { try await api.me() }
            account.noteUser(user)
            let owned = try await call { try await api.cosmetics() }
            guard isSignedIn, account.user?.id == user.id else { return }
            serverOwned = owned
        } catch {
            // Tried again on the next refresh.
        }
    }

    /// Brings this phone's coins and items over to the signed-in account (`POST /me/coins/import`),
    /// unless they've gone to it already. Call before saving a Lockling to the account: the
    /// server only lets it wear parts the account owns. A 409 `already_imported` counts as done;
    /// offline, it's tried again next time.
    public func importIfNeeded() async {
        if let importTask {
            await importTask.value
            return
        }
        guard isSignedIn, let userId = account.user?.id, !wallet.imported.contains(userId) else { return }
        let task = Task { await self.runImport(for: userId) }
        importTask = task
        await task.value
        importTask = nil
    }

    private func runImport(for userId: String) async {
        let coins = localCoins
        // Plus items aren't bought, and the server skips them anyway.
        let items = wallet.owned.filter { ShopCatalogue.item(id: $0)?.plus == false }
        do {
            let result = try await call { try await api.importCoins(coins: coins, owned: items) }
            markImported(userId)
            account.noteUser(result.user)
            if isSignedIn, account.user?.id == userId {
                serverOwned = result.owned
            }
        } catch let error as APIError where error.code == .alreadyImported {
            markImported(userId)
        } catch {
            Log.api.error("Couldn't bring this phone's coins over to the account")
        }
    }

    private func markImported(_ userId: String) {
        guard !wallet.imported.contains(userId) else { return }
        wallet.imported.append(userId)
        storage.save(wallet)
    }

    // MARK: - Buying

    /// Buys `item`: from the account signed in, from this phone's coins signed out. Something you
    /// own already is left alone. Throws `APIError`: `notEnoughCoins`, `plusRequired` (Plus items
    /// aren't sold: open the paywall), `itemNotFound`, or the usual offline and server errors.
    public func buy(_ item: ShopItem) async throws {
        guard !owns(item), buying == nil else { return }
        if isSignedIn {
            buying = item.id
            defer { buying = nil }
            do {
                let result = try await call { try await api.buy(itemId: item.id) }
                account.noteCoins(result.coins)
                if isSignedIn {
                    serverOwned = result.owned
                }
            } catch let error as APIError where error.code == .alreadyOwned {
                // Bought on another phone, or Plus has it: catch up with what's owned.
                if let owned = try? await call({ try await api.cosmetics() }), isSignedIn {
                    serverOwned = owned
                }
            }
        } else {
            guard !item.plus else {
                throw APIError.server(status: 402, code: .plusRequired, message: nil)
            }
            guard localCoins >= item.price else {
                throw APIError.server(status: 402, code: .notEnoughCoins, message: nil)
            }
            wallet.spent += item.price
            wallet.owned.append(item.id)
            storage.save(wallet)
        }
    }

    /// The free parts `avatar` wears become this phone's, signed out: the Lockling made in
    /// onboarding is free to make (SPEC.md §1.1, "pick your creature"). Defaults and Plus parts
    /// aren't items to keep.
    public func keepParts(of avatar: AvatarCode) {
        let new = ShopCatalogue.freeItemIDs(wornBy: avatar).filter { !wallet.owned.contains($0) }
        guard !new.isEmpty else { return }
        wallet.owned += new
        storage.save(wallet)
    }

    // MARK: - Plumbing

    /// Runs an API call; a 401 ends the session before the error goes on.
    private func call<Value>(_ request: @MainActor () async throws -> Value) async throws -> Value {
        do {
            return try await request()
        } catch let error as APIError where error.isUnauthorised {
            account.endSession()
            throw error
        }
    }
}
