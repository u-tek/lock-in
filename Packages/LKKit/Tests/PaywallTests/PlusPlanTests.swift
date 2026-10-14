import Foundation
import Testing
@testable import Paywall

@Suite struct PlusPlanTests {
    @Test func plansInTheOrderTheyreOffered() {
        #expect(PlusPlan.allCases == [.yearly, .monthly, .lifetime])
        #expect(PlusPlan.allCases.map(\.id) == ["yearly", "monthly", "lifetime"])
    }

    @Test func productIDsFollowTheBundleID() {
        #expect(PlusPlan.yearly.productID(bundleID: "app.lockin") == "app.lockin.plus.yearly")
        #expect(PlusPlan.monthly.productID(bundleID: "app.lockin") == "app.lockin.plus.monthly")
        #expect(PlusPlan.lifetime.productID(bundleID: "app.lockin") == "app.lockin.plus.lifetime")
    }

    @Test func productIDsMapBackToPlans() {
        for plan in PlusPlan.allCases {
            #expect(PlusPlan(productID: plan.productID(bundleID: "app.lockin"), bundleID: "app.lockin") == plan)
        }
        #expect(PlusPlan(productID: "app.lockin.plus.weekly", bundleID: "app.lockin") == nil)
        #expect(PlusPlan(productID: "other.app.plus.yearly", bundleID: "app.lockin") == nil)
        #expect(PlusPlan(productID: "yearly", bundleID: "app.lockin") == nil)
    }

    @Test func fallbackPricesAreTheStartingPrices() {
        #expect(PlusPlan.yearly.fallbackPrice == "A$24.99")
        #expect(PlusPlan.monthly.fallbackPrice == "A$3.99")
        #expect(PlusPlan.lifetime.fallbackPrice == "A$49.99")
    }

    @Test func yearlyPerMonthIsRoundedToTheCent() {
        #expect(PlusPlan.monthlyEquivalent(ofYearly: Decimal(2_499) / 100) == Decimal(208) / 100)
        #expect(PlusPlan.monthlyEquivalent(ofYearly: Decimal(1_499) / 100) == Decimal(125) / 100)
        #expect(PlusPlan.monthlyEquivalent(ofYearly: Decimal(1_199) / 100) == 1)
        #expect(PlusPlan.monthlyEquivalent(ofYearly: 120) == 10)
        #expect(PlusPlan.fallbackMonthlyEquivalent == "A$2.08")
    }

    @Test func amountsHaveTwoDecimalsAndNoGrouping() {
        #expect(PlusPlan.amountText(1) == "1.00")
        #expect(PlusPlan.amountText(Decimal(123_456) / 100) == "1234.56")
    }

    @Test func callToActionPerPlan() {
        #expect(PlusPlan.yearly.callToAction(trialAvailable: true) == "Try it free")
        #expect(PlusPlan.yearly.callToAction(trialAvailable: false) == "Continue")
        for plan in [PlusPlan.monthly, .lifetime] {
            #expect(plan.callToAction(trialAvailable: true) == "Continue")
            #expect(plan.callToAction(trialAvailable: false) == "Continue")
        }
    }

    @Test func disclosureNamesThePriceAndRenewal() {
        #expect(PlusPlan.yearly.disclosure(price: "A$24.99", trialAvailable: true)
            == "7 days free, then A$24.99/year. Renews automatically until you cancel in Settings.")
        #expect(PlusPlan.yearly.disclosure(price: "A$24.99", trialAvailable: false)
            == "A$24.99/year. Renews automatically until you cancel in Settings.")
        #expect(PlusPlan.monthly.disclosure(price: "A$3.99", trialAvailable: true)
            == "A$3.99/month. Renews automatically until you cancel in Settings.")
        #expect(PlusPlan.lifetime.disclosure(price: "A$49.99", trialAvailable: true)
            == "A$49.99 once. Not a subscription.")
    }

    @Test func onlySubscriptionsRenew() {
        #expect(PlusPlan.yearly.isSubscription)
        #expect(PlusPlan.monthly.isSubscription)
        #expect(!PlusPlan.lifetime.isSubscription)
        #expect(PlusPlan.allCases.filter(\.hasFreeTrial) == [.yearly])
    }
}
