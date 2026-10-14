import Foundation
import RevenueCat
import Testing
@testable import Paywall

// RevenueCat behind PlusStore (M7): which package sells which plan, and what its errors say. Never
// configures the SDK: there's no key, and no network, in the tests.

@Suite struct RevenueCatPlanTests {
    @Test func packageTypesPickThePlan() {
        #expect(RevenueCatPurchases.plan(packageType: .annual, productID: "anything") == .yearly)
        #expect(RevenueCatPurchases.plan(packageType: .monthly, productID: "anything") == .monthly)
        #expect(RevenueCatPurchases.plan(packageType: .lifetime, productID: "anything") == .lifetime)
    }

    /// A custom package falls back on its product id: docs/milestones/M7.md's "lockin.plus.<plan>"
    /// or the bundle id's "<bundle id>.plus.<plan>".
    @Test func customPackagesGoByProductID() {
        #expect(RevenueCatPurchases.plan(packageType: .custom, productID: "lockin.plus.yearly") == .yearly)
        #expect(RevenueCatPurchases.plan(packageType: .custom, productID: "app.lockin.plus.monthly") == .monthly)
        #expect(RevenueCatPurchases.plan(packageType: .unknown, productID: "lockin_plus_lifetime") == .lifetime)
        #expect(RevenueCatPurchases.plan(packageType: .weekly, productID: "lockin.coins.small") == nil)
        #expect(RevenueCatPurchases.plan(packageType: .sixMonth, productID: "lockin.plus.sixmonth") == nil)
    }

    @Test func theEntitlementAndOfferingAreTheContracts() {
        #expect(RevenueCatPurchases.entitlement == "plus")
        #expect(RevenueCatPurchases.offering == "default")
    }
}

@Suite struct RevenueCatErrorTests {
    @Test func cancellingAndWaitingAreNotErrors() {
        #expect(PlusStoreError(revenueCat: ErrorCode.purchaseCancelledError) == nil)
        #expect(PlusStoreError(revenueCat: ErrorCode.paymentPendingError) == nil)
    }

    @Test func revenueCatsErrorsBecomeFriendlyOnes() {
        #expect(PlusStoreError(revenueCat: ErrorCode.networkError) == .network)
        #expect(PlusStoreError(revenueCat: ErrorCode.offlineConnectionError) == .network)
        #expect(PlusStoreError(revenueCat: ErrorCode.purchaseNotAllowedError) == .notAllowed)
        #expect(PlusStoreError(revenueCat: ErrorCode.productNotAvailableForPurchaseError) == .unavailable)
        #expect(PlusStoreError(revenueCat: ErrorCode.configurationError) == .unavailable)
        #expect(PlusStoreError(revenueCat: ErrorCode.storeProblemError) == .failed)
        #expect(PlusStoreError(revenueCat: PlusStoreError.unverified) == .unverified)
        #expect(PlusStoreError(revenueCat: CocoaError(.fileNoSuchFile)) == .failed)
    }
}
