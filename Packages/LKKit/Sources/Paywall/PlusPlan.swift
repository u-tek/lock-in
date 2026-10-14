import Foundation

/// The ways to buy Lockin Plus (SPEC.md §2). Prices are the starting prices to test; the App
/// Store's own (`PlusStore.displayPrice(for:)`) replace them once the products load.
public enum PlusPlan: String, CaseIterable, Identifiable, Sendable {
    case yearly
    case monthly
    case lifetime

    public var id: String { rawValue }

    /// Shown until the App Store's prices load, and when they can't.
    public var fallbackPrice: String {
        Self.fallbackCurrency + Self.amountText(fallbackAmount)
    }

    /// The App Store Connect product id: "<bundle id>.plus.yearly" and so on.
    public func productID(bundleID: String) -> String {
        "\(bundleID).plus.\(rawValue)"
    }

    /// The plan a product id belongs to, or nil for anything else.
    init?(productID: String, bundleID: String) {
        guard let plan = Self.allCases.first(where: { $0.productID(bundleID: bundleID) == productID }) else {
            return nil
        }
        self = plan
    }

    var title: String {
        switch self {
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        case .lifetime: "Lifetime"
        }
    }

    /// Under the price on the plan's card. Lifetime says "Pay once" beside its title instead.
    var period: String? {
        switch self {
        case .yearly: "per year"
        case .monthly: "per month"
        case .lifetime: nil
        }
    }

    /// The renewal unit in the disclosure line: "A$24.99/year".
    var periodUnit: String? {
        switch self {
        case .yearly: "year"
        case .monthly: "month"
        case .lifetime: nil
        }
    }

    var isSubscription: Bool {
        periodUnit != nil
    }

    /// The yearly plan carries the free trial: an introductory offer set up in App Store Connect.
    var hasFreeTrial: Bool {
        self == .yearly
    }

    static let trialDays = 7

    /// The main button's title. "Try it free" only when a trial is actually on offer: App Review
    /// rejects a free-trial button that charges straight away.
    func callToAction(trialAvailable: Bool) -> String {
        hasFreeTrial && trialAvailable ? "Try it free" : "Continue"
    }

    /// The one line under the button that App Review requires: what's charged, how often, and
    /// that a subscription renews until cancelled.
    func disclosure(price: String, trialAvailable: Bool) -> String {
        guard let periodUnit else { return "\(price) once. Not a subscription." }
        let renewal = "Renews automatically until you cancel in Settings."
        if hasFreeTrial && trialAvailable {
            return "\(Self.trialDays) days free, then \(price)/\(periodUnit). \(renewal)"
        }
        return "\(price)/\(periodUnit). \(renewal)"
    }

    // MARK: - Prices

    /// SPEC.md §2's starting prices, in Australian dollars.
    static let fallbackCurrency = "A$"

    var fallbackAmount: Decimal {
        switch self {
        case .yearly: Decimal(2_499) / 100
        case .monthly: Decimal(399) / 100
        case .lifetime: Decimal(4_999) / 100
        }
    }

    /// The yearly price spread over 12 months, rounded to the cent.
    static func monthlyEquivalent(ofYearly price: Decimal) -> Decimal {
        var perMonth = price / 12
        var rounded = Decimal()
        NSDecimalRound(&rounded, &perMonth, 2, .plain)
        return rounded
    }

    /// "A$2.08" for the fallback yearly price.
    static var fallbackMonthlyEquivalent: String {
        fallbackCurrency + amountText(monthlyEquivalent(ofYearly: PlusPlan.yearly.fallbackAmount))
    }

    /// Two decimals, a full stop and no grouping, whatever the phone's region: these fallbacks
    /// stand in for prices the App Store would format itself.
    static func amountText(_ amount: Decimal) -> String {
        amount.formatted(
            .number
                .precision(.fractionLength(2))
                .grouping(.never)
                .locale(Locale(identifier: "en_AU"))
        )
    }
}
