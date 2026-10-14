import Combine
import Core
import Foundation
import StoreKit
import SwiftUI

/// Why a purchase didn't go through, in words for the alert.
public enum PlusStoreError: Error, Equatable, Sendable, LocalizedError {
    /// The products didn't load: not set up in App Store Connect yet (M7), offline when the
    /// paywall opened, or not sold in this storefront.
    case unavailable
    /// In-app purchases are switched off in Screen Time.
    case notAllowed
    case network
    /// The App Store's signature on the transaction didn't check out.
    case unverified
    case failed

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Purchases aren't available yet. Please try again later."
        case .notAllowed: "Purchases are turned off on this iPhone in Screen Time."
        case .network: "Couldn't reach the App Store. Check your connection and try again."
        case .unverified: "The App Store couldn't confirm this purchase. Try Restore in a moment."
        case .failed: "Something went wrong with the App Store. Please try again."
        }
    }

    /// Sorts what StoreKit threw. Nil when the person cancelled, which isn't an error.
    init?(_ error: Error) {
        if let error = error as? PlusStoreError {
            self = error
            return
        }
        if let error = error as? StoreKitError {
            switch error {
            case .userCancelled: return nil
            case .networkError: self = .network
            case .notAvailableInStorefront: self = .unavailable
            default: self = .failed
            }
            return
        }
        if let error = error as? Product.PurchaseError {
            switch error {
            case .productUnavailable: self = .unavailable
            case .purchaseNotAllowed: self = .notAllowed
            default: self = .failed
            }
            return
        }
        self = .failed
    }
}

/// Lockin Plus: the products, whether this person has Plus, buying and restoring.
///
/// Through RevenueCat when the build has its public key (`LK_REVENUECAT_KEY`, M7), on StoreKit 2
/// directly when it doesn't, so a build without RevenueCat still sells Plus. Either way Plus is on
/// when this Apple Account bought it, or when the signed-in Lockin account has it (`User.plusUntil`:
/// bought on another phone, or the server says so). After any purchase or restore the app has the
/// server check with RevenueCat (`afterPurchase`, `POST /me/plus/refresh`).
@MainActor
public final class PlusStore: ObservableObject {
    @Published public private(set) var isPlus: Bool
    /// The App Store's products by plan. Empty until `load()` finishes, and when they don't exist
    /// yet; the paywall shows the fallback prices meanwhile. Through RevenueCat, the StoreKit 2
    /// products behind its packages.
    @Published private(set) var products: [PlusPlan: Product] = [:]
    /// RevenueCat's own prices, for a package without a StoreKit 2 product behind it.
    @Published private(set) var revenueCatPrices: [PlusPlan: String] = [:]
    @Published private(set) var revenueCatYearlyPerMonth: String?
    /// Whether the yearly plan's free trial is on offer to this Apple Account. Assumed until the
    /// products load: the fallback prices advertise it too.
    @Published private(set) var isTrialAvailable = true

    /// Plus from this Apple Account's purchases: StoreKit's current entitlements, or RevenueCat's
    /// `plus` entitlement. Settings offers "Manage subscription" for these.
    @Published public private(set) var hasPurchasedPlus: Bool
    /// The signed-in Lockin account's Plus, as the server last said (`User.plusUntil`, Unix
    /// seconds; lifetime is year 9999).
    @Published public private(set) var accountPlusUntil: Double?
    /// The Lockin account RevenueCat knows this person as; nil when signed out (anonymous).
    private(set) var accountID: String?

    /// Counts paywall views, trials and purchases. Event counts only.
    public var analytics: Analytics = .debugLog
    /// Runs after a purchase or a restore that went through: the app has the server check Plus with
    /// RevenueCat (`POST /me/plus/refresh`), so squad limits and Squad Boost follow at once.
    public var afterPurchase: (@MainActor @Sendable () async -> Void)?

    let bundleID: String
    /// Snapshots and SwiftUI previews: no StoreKit, no RevenueCat.
    let isPreview: Bool
    /// RevenueCat, when the build has its key; nil buys through StoreKit 2.
    let revenueCat: RevenueCatPurchases?
    /// Listens for purchases made outside the paywall: renewals, Ask to Buy approvals, refunds,
    /// offer codes (StoreKit's transactions, or RevenueCat's customer). Started by the first
    /// `load()` and kept for the life of the app.
    private(set) var updatesTask: Task<Void, Never>?
    /// Telling RevenueCat about the account, one change at a time.
    private var identifyTask: Task<Void, Never>?

    /// - Parameter revenueCatKey: RevenueCat's public API key (`AppConfiguration.revenueCatAPIKey`);
    ///   nil or empty keeps StoreKit 2.
    public init(bundleID: String, revenueCatKey: String? = nil) {
        self.bundleID = bundleID
        self.isPlus = false
        self.hasPurchasedPlus = false
        self.isPreview = false
        if let key = revenueCatKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            revenueCat = RevenueCatPurchases(apiKey: key)
        } else {
            revenueCat = nil
        }
    }

    private init(previewIsPlus: Bool) {
        self.bundleID = "preview"
        self.isPlus = previewIsPlus
        self.hasPurchasedPlus = previewIsPlus
        self.isPreview = true
        revenueCat = nil
        analytics = .disabled
    }

    /// A store that never calls StoreKit, for snapshots and SwiftUI previews.
    public static func preview(isPlus: Bool = false) -> PlusStore {
        PlusStore(previewIsPlus: isPlus)
    }

    /// Purchases go through RevenueCat.
    public var usesRevenueCat: Bool {
        revenueCat != nil
    }

    /// The account's Plus is lifetime (`plusUntil` in year 9999).
    public var isLifetimeOnAccount: Bool {
        guard let accountPlusUntil else { return false }
        return accountPlusUntil >= Self.lifetimeFrom
    }

    /// The server writes lifetime Plus as 9999-12-31 (253402300799); anything from the year 9000
    /// on counts.
    static let lifetimeFrom: Double = 221_845_392_000

    var productIDs: [String] {
        PlusPlan.allCases.map { $0.productID(bundleID: bundleID) }
    }

    // MARK: - The account (M7)

    /// The signed-in Lockin account, whenever it changes: its Plus counts too, and RevenueCat knows
    /// purchases by its id (`logIn`; `logOut` when it's nil, signed out). Without a key only the
    /// Plus is kept.
    public func noteAccount(id: String?, plusUntil: Double?) {
        accountPlusUntil = plusUntil
        updatePlus()
        guard !isPreview, id != accountID else { return }
        accountID = id
        identifyWithRevenueCat()
    }

    /// Plus on the account at `now`: `plusUntil` still ahead.
    nonisolated static func accountHasPlus(until plusUntil: Double?, now: Date) -> Bool {
        guard let plusUntil, plusUntil.isFinite else { return false }
        return plusUntil > now.timeIntervalSince1970
    }

    private func updatePlus(now: Date = Date()) {
        let plus = hasPurchasedPlus || Self.accountHasPlus(until: accountPlusUntil, now: now)
        if plus != isPlus {
            isPlus = plus
        }
    }

    private func notePurchasedPlus(_ plus: Bool) {
        if plus != hasPurchasedPlus {
            hasPurchasedPlus = plus
        }
        updatePlus()
    }

    /// Before RevenueCat is configured there's no one to tell: `load()` configures it as the
    /// account.
    private func identifyWithRevenueCat() {
        guard let revenueCat, revenueCat.isConfigured else { return }
        let id = accountID
        let previous = identifyTask
        identifyTask = Task { [weak self] in
            await previous?.value
            guard let plus = await revenueCat.identify(id) else { return }
            self?.notePurchasedPlus(plus)
        }
    }

    /// After a purchase or a restore: the server checks too. In the background, so the paywall
    /// closes at once; the account's answer arrives through `noteAccount`.
    private func tellServer() {
        guard let afterPurchase else { return }
        Task {
            await afterPurchase()
        }
    }

    // MARK: - Loading

    /// Fetches the products and works out whether this Apple Account has Plus. Call at launch;
    /// the paywall calls it again when it opens, in case the first try was offline.
    public func load() async {
        guard !isPreview else { return }
        updatePlus()
        if let revenueCat {
            await loadRevenueCat(revenueCat)
        } else {
            await loadStoreKit()
        }
    }

    private func loadStoreKit() async {
        listenForTransactions()
        do {
            let loaded = try await Product.products(for: productIDs)
            var byPlan: [PlusPlan: Product] = [:]
            for product in loaded {
                if let plan = PlusPlan(productID: product.id, bundleID: bundleID) {
                    byPlan[plan] = product
                }
            }
            products = byPlan
            await noteTrialEligibility(byPlan)
        } catch {
            Log.app.error("Couldn't load the Plus products")
        }
        await refreshEntitlements()
    }

    private func loadRevenueCat(_ revenueCat: RevenueCatPurchases) async {
        revenueCat.configure(userID: accountID)
        if updatesTask == nil {
            updatesTask = revenueCat.watchPlus { [weak self] plus in
                self?.notePurchasedPlus(plus)
            }
        }
        do {
            let plans = try await revenueCat.loadPlans()
            products = plans.compactMapValues(\.product)
            revenueCatPrices = plans.mapValues(\.price)
            revenueCatYearlyPerMonth = plans[.yearly]?.pricePerMonth
            await noteTrialEligibility(products)
        } catch {
            Log.app.error("Couldn't load Lockin Plus's offering from RevenueCat")
        }
        if let plus = await revenueCat.currentPlus() {
            notePurchasedPlus(plus)
        }
    }

    /// The yearly plan's trial is on offer: set up in App Store Connect, and this Apple Account
    /// hasn't had it.
    private func noteTrialEligibility(_ byPlan: [PlusPlan: Product]) async {
        guard let subscription = byPlan[.yearly]?.subscription else { return }
        if subscription.introductoryOffer != nil {
            isTrialAvailable = await subscription.isEligibleForIntroOffer
        } else {
            isTrialAvailable = false
        }
    }

    // MARK: - Prices

    /// The App Store's price for the plan in the person's currency, or the fallback until the
    /// products load.
    public func displayPrice(for plan: PlusPlan) -> String {
        products[plan]?.displayPrice ?? revenueCatPrices[plan] ?? plan.fallbackPrice
    }

    /// The yearly price per month in the same currency, for its card: "A$2.08".
    func monthlyEquivalentOfYearly() -> String {
        guard let yearly = products[.yearly] else {
            return revenueCatYearlyPerMonth ?? PlusPlan.fallbackMonthlyEquivalent
        }
        return PlusPlan.monthlyEquivalent(ofYearly: yearly.price).formatted(yearly.priceFormatStyle)
    }

    // MARK: - Buying

    /// Buys the plan. True when it went through and Plus is unlocked; false when the person
    /// cancelled or it's waiting for approval (Ask to Buy). Throws `PlusStoreError`.
    public func purchase(_ plan: PlusPlan) async throws -> Bool {
        guard !isPreview else { return false }
        if let revenueCat {
            return try await runRevenueCatPurchase(of: plan, with: revenueCat)
        }
        return try await runPurchase(of: plan) { product in
            try await product.purchase()
        }
    }

    /// The same through SwiftUI's purchase action, which shows the sheet over the paywall's own
    /// scene. RevenueCat finds the scene itself.
    func purchase(_ plan: PlusPlan, using action: PurchaseAction) async throws -> Bool {
        guard !isPreview else { return false }
        if let revenueCat {
            return try await runRevenueCatPurchase(of: plan, with: revenueCat)
        }
        return try await runPurchase(of: plan) { product in
            try await action(product)
        }
    }

    private func runPurchase(
        of plan: PlusPlan,
        performing buy: @MainActor (Product) async throws -> Product.PurchaseResult
    ) async throws -> Bool {
        guard !isPreview else { return false }
        guard let product = products[plan] else { throw PlusStoreError.unavailable }
        let trial = plan.hasFreeTrial && isTrialAvailable
        let result: Product.PurchaseResult
        do {
            result = try await buy(product)
        } catch {
            guard let reason = PlusStoreError(error) else { return false }
            Log.app.error("Plus purchase failed")
            throw reason
        }
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await refreshEntitlements()
            analytics.track(trial ? .trialStarted : .purchaseCompleted)
            tellServer()
            return true
        case .success(.unverified):
            throw PlusStoreError.unverified
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    private func runRevenueCatPurchase(of plan: PlusPlan, with revenueCat: RevenueCatPurchases) async throws -> Bool {
        let trial = plan.hasFreeTrial && isTrialAvailable
        let outcome: Bool?
        do {
            outcome = try await revenueCat.purchase(plan)
        } catch {
            Log.app.error("Plus purchase failed")
            throw error as? PlusStoreError ?? .failed
        }
        // Cancelled, or waiting for approval.
        guard let plus = outcome else { return false }
        notePurchasedPlus(plus)
        analytics.track(trial ? .trialStarted : .purchaseCompleted)
        tellServer()
        if !plus {
            // Paid, but RevenueCat's `plus` entitlement isn't on: its dashboard needs the product.
            Log.app.error("A Plus purchase went through without the plus entitlement")
        }
        return isPlus
    }

    /// Asks the App Store for this Apple Account's purchases (it may ask them to sign in), then
    /// checks for Plus again, and has the server check too.
    public func restore() async {
        guard !isPreview else { return }
        if let revenueCat {
            if let plus = await revenueCat.restore() {
                notePurchasedPlus(plus)
            }
        } else {
            do {
                try await AppStore.sync()
            } catch {
                // Cancelling the sign-in lands here too; the paywall says if nothing was found.
                Log.app.error("Restoring purchases didn't finish")
            }
            await refreshEntitlements()
        }
        tellServer()
    }

    // MARK: - StoreKit's entitlements (without RevenueCat)

    func refreshEntitlements() async {
        guard !isPreview, revenueCat == nil else { return }
        let ids = Set(productIDs)
        let active = await Self.hasActiveEntitlement(productIDs: ids)
        notePurchasedPlus(active)
    }

    private func listenForTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    /// Reads the current entitlements off the main actor.
    private nonisolated static func hasActiveEntitlement(productIDs: Set<String>) async -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if grantsPlus(
                productID: transaction.productID,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                productIDs: productIDs,
                now: Date()
            ) {
                return true
            }
        }
        return false
    }

    /// Plus is on for one of our products that hasn't been refunded and, for a subscription,
    /// hasn't run out. The current entitlements leave most of these out already; this holds
    /// either way.
    nonisolated static func grantsPlus(
        productID: String,
        revocationDate: Date?,
        expirationDate: Date?,
        productIDs: Set<String>,
        now: Date
    ) -> Bool {
        guard productIDs.contains(productID), revocationDate == nil else { return false }
        if let expirationDate, expirationDate <= now {
            return false
        }
        return true
    }
}
