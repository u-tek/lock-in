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

/// Lockin Plus on StoreKit 2: the products, whether this Apple Account has Plus, buying and
/// restoring. RevenueCat takes over in M7.
@MainActor
public final class PlusStore: ObservableObject {
    @Published public private(set) var isPlus: Bool
    /// The App Store's products by plan. Empty until `load()` finishes, and when they don't exist
    /// yet; the paywall shows the fallback prices meanwhile.
    @Published private(set) var products: [PlusPlan: Product] = [:]
    /// Whether the yearly plan's free trial is on offer to this Apple Account. Assumed until the
    /// products load: the fallback prices advertise it too.
    @Published private(set) var isTrialAvailable = true

    /// Counts paywall views, trials and purchases. Event counts only.
    public var analytics: Analytics = .debugLog

    let bundleID: String
    /// Snapshots and SwiftUI previews: no StoreKit at all.
    let isPreview: Bool
    /// Listens for purchases made outside the paywall: renewals, Ask to Buy approvals, refunds,
    /// offer codes. Started by the first `load()` and kept for the life of the app.
    private(set) var updatesTask: Task<Void, Never>?

    public init(bundleID: String) {
        self.bundleID = bundleID
        self.isPlus = false
        self.isPreview = false
    }

    private init(previewIsPlus: Bool) {
        self.bundleID = "preview"
        self.isPlus = previewIsPlus
        self.isPreview = true
        analytics = .disabled
    }

    /// A store that never calls StoreKit, for snapshots and SwiftUI previews.
    public static func preview(isPlus: Bool = false) -> PlusStore {
        PlusStore(previewIsPlus: isPlus)
    }

    var productIDs: [String] {
        PlusPlan.allCases.map { $0.productID(bundleID: bundleID) }
    }

    /// Fetches the products and works out whether this Apple Account has Plus. Call at launch;
    /// the paywall calls it again when it opens, in case the first try was offline.
    public func load() async {
        guard !isPreview else { return }
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
            if let subscription = byPlan[.yearly]?.subscription {
                // No introductory offer set up, or this Apple Account has had the trial before.
                if subscription.introductoryOffer != nil {
                    isTrialAvailable = await subscription.isEligibleForIntroOffer
                } else {
                    isTrialAvailable = false
                }
            }
        } catch {
            Log.app.error("Couldn't load the Plus products")
        }
        await refreshEntitlements()
    }

    /// The App Store's price for the plan in the person's currency, or the fallback until the
    /// products load.
    public func displayPrice(for plan: PlusPlan) -> String {
        products[plan]?.displayPrice ?? plan.fallbackPrice
    }

    /// The yearly price per month in the same currency, for its card: "A$2.08".
    func monthlyEquivalentOfYearly() -> String {
        guard let yearly = products[.yearly] else { return PlusPlan.fallbackMonthlyEquivalent }
        return PlusPlan.monthlyEquivalent(ofYearly: yearly.price).formatted(yearly.priceFormatStyle)
    }

    /// Buys the plan. True when it went through and Plus is unlocked; false when the person
    /// cancelled or it's waiting for approval (Ask to Buy). Throws `PlusStoreError`.
    public func purchase(_ plan: PlusPlan) async throws -> Bool {
        try await runPurchase(of: plan) { product in
            try await product.purchase()
        }
    }

    /// The same through SwiftUI's purchase action, which shows the sheet over the paywall's own
    /// scene.
    func purchase(_ plan: PlusPlan, using action: PurchaseAction) async throws -> Bool {
        try await runPurchase(of: plan) { product in
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
            return true
        case .success(.unverified):
            throw PlusStoreError.unverified
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Asks the App Store for this Apple Account's purchases (it may ask them to sign in), then
    /// checks for Plus again.
    public func restore() async {
        guard !isPreview else { return }
        do {
            try await AppStore.sync()
        } catch {
            // Cancelling the sign-in lands here too; the paywall says if nothing was found.
            Log.app.error("Restoring purchases didn't finish")
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        guard !isPreview else { return }
        let ids = Set(productIDs)
        let active = await Self.hasActiveEntitlement(productIDs: ids)
        if active != isPlus {
            isPlus = active
        }
    }

    private func listenForTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    /// Reads the current entitlements off the main actor.
    private nonisolated static func hasActiveEntitlement(productIDs: Set<String>) async -> Bool {
        for await result in Transaction.currentEntitlements {
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
