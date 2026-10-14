import Core
import Foundation
import RevenueCat
import StoreKit

// RevenueCat behind `PlusStore` (M7, docs/milestones/M7.md): configured with the build's public
// key (`LK_REVENUECAT_KEY`), it sells the `default` offering's three packages and says whether the
// `plus` entitlement is on. Its own file, so RevenueCat's type names (it has a `Transaction` and a
// `VerificationResult` of its own) never meet StoreKit's in PlusStore.swift. Only `Product`, which
// RevenueCat doesn't have, is used from StoreKit here.

/// What the paywall needs to know about one plan's package.
struct RevenueCatPlan: Sendable {
    /// StoreKit's product behind the package (StoreKit 2), for its price and its trial.
    let product: Product?
    /// RevenueCat's price, in the person's currency: "A$24.99".
    let price: String
    /// The price per month, for the yearly plan's card: "A$2.08".
    let pricePerMonth: String?
}

/// Lockin Plus through RevenueCat's SDK. `PlusStore` makes one only when the build has a key, and
/// nothing here touches RevenueCat before `configure(userID:)`.
@MainActor
final class RevenueCatPurchases {
    /// RevenueCat's entitlement for Plus.
    nonisolated static let entitlement = "plus"
    /// The offering with the three plans, when RevenueCat has no current one.
    nonisolated static let offering = "default"

    private let apiKey: String
    /// `Purchases` has been configured: nothing may call it before.
    private(set) var isConfigured = false
    /// The current offering's packages, by plan.
    private var packages: [PlusPlan: Package] = [:]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Configures the SDK, once, as the Lockin account `userID`, or anonymous before signing in.
    func configure(userID: String?) {
        guard !isConfigured else { return }
        isConfigured = true
        // Configured already (by an earlier store in this process): keep it.
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey, appUserID: userID)
    }

    /// The plans' packages, from the current offering (else `default`). Throws what RevenueCat
    /// threw.
    func loadPlans() async throws -> [PlusPlan: RevenueCatPlan] {
        guard isConfigured else { return [:] }
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.current ?? offerings.all[Self.offering] else {
            Log.app.error("RevenueCat has no offering for Lockin Plus")
            packages = [:]
            return [:]
        }
        var byPlan: [PlusPlan: Package] = [:]
        for package in offering.availablePackages {
            guard let plan = Self.plan(packageType: package.packageType, productID: package.storeProduct.productIdentifier) else {
                continue
            }
            if byPlan[plan] == nil {
                byPlan[plan] = package
            }
        }
        packages = byPlan
        return byPlan.mapValues { package in
            let product = package.storeProduct
            return RevenueCatPlan(product: product.sk2Product, price: product.localizedPriceString, pricePerMonth: product.localizedPricePerMonth)
        }
    }

    /// The plan a package sells: by its type (Annual, Monthly, Lifetime in RevenueCat's
    /// dashboard), else by its product id ("….plus.yearly").
    nonisolated static func plan(packageType: PackageType, productID: String) -> PlusPlan? {
        switch packageType {
        case .annual: return .yearly
        case .monthly: return .monthly
        case .lifetime: return .lifetime
        default:
            return PlusPlan.allCases.first { plan in
                productID.hasSuffix(".plus.\(plan.rawValue)") || productID.hasSuffix("_plus_\(plan.rawValue)")
            }
        }
    }

    /// Buys the plan's package. Nil when the person cancelled or it's waiting for approval (Ask to
    /// Buy); otherwise whether Plus is on now. Throws `PlusStoreError`.
    func purchase(_ plan: PlusPlan) async throws -> Bool? {
        guard isConfigured, let package = packages[plan] else { throw PlusStoreError.unavailable }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            return result.userCancelled ? nil : Self.hasPlus(result.customerInfo)
        } catch {
            if let failure = PlusStoreError(revenueCat: error) {
                throw failure
            }
            return nil
        }
    }

    /// Restores this Apple Account's purchases. Whether Plus is on, or nil when it didn't finish.
    func restore() async -> Bool? {
        guard isConfigured else { return nil }
        do {
            return Self.hasPlus(try await Purchases.shared.restorePurchases())
        } catch {
            // Cancelling the App Store's sign-in lands here too; the paywall says if nothing was found.
            Log.app.error("Restoring purchases through RevenueCat didn't finish")
            return nil
        }
    }

    /// Whether Plus is on now, as RevenueCat has it; nil when it couldn't say.
    func currentPlus() async -> Bool? {
        guard isConfigured else { return nil }
        do {
            return Self.hasPlus(try await Purchases.shared.customerInfo())
        } catch {
            Log.app.error("Couldn't read Lockin Plus from RevenueCat")
            return nil
        }
    }

    /// Tells RevenueCat who this is: `logIn` with the Lockin account's id, so purchases follow the
    /// account to other phones and the server's webhook knows whose they are, or `logOut` back to
    /// anonymous after signing out. Whether Plus is on afterwards; nil when nothing changed or it
    /// didn't work.
    func identify(_ userID: String?) async -> Bool? {
        guard isConfigured else { return nil }
        let purchases = Purchases.shared
        do {
            if let userID {
                guard purchases.appUserID != userID else { return nil }
                let result = try await purchases.logIn(userID)
                return Self.hasPlus(result.customerInfo)
            }
            // Logging out an anonymous customer is an error in RevenueCat: there's no one to forget.
            guard !purchases.isAnonymous else { return nil }
            return Self.hasPlus(try await purchases.logOut())
        } catch {
            Log.app.error("Couldn't tell RevenueCat about the account")
            return nil
        }
    }

    /// Calls `onChange` with whether Plus is on each time RevenueCat's customer changes: renewals,
    /// expiries, refunds, purchases made elsewhere. Runs until the task is cancelled.
    func watchPlus(_ onChange: @escaping @MainActor @Sendable (Bool) -> Void) -> Task<Void, Never>? {
        guard isConfigured else { return nil }
        let updates = Purchases.shared.customerInfoStream
        return Task {
            for await info in updates {
                onChange(Self.hasPlus(info))
            }
        }
    }

    nonisolated static func hasPlus(_ info: CustomerInfo) -> Bool {
        info.entitlements[entitlement]?.isActive == true
    }
}

extension PlusStoreError {
    /// Sorts what RevenueCat threw. Nil when the person cancelled, or the purchase waits for
    /// approval (Ask to Buy): neither is an error.
    init?(revenueCat error: any Error) {
        if let error = error as? PlusStoreError {
            self = error
            return
        }
        guard let code = error as? ErrorCode else {
            self = .failed
            return
        }
        switch code {
        case .purchaseCancelledError, .paymentPendingError:
            return nil
        case .networkError, .offlineConnectionError:
            self = .network
        case .purchaseNotAllowedError:
            self = .notAllowed
        case .productNotAvailableForPurchaseError, .configurationError, .invalidCredentialsError:
            self = .unavailable
        default:
            self = .failed
        }
    }
}
