import Core
import Creature
import DesignSystem
import Model
import StoreKit
import SwiftUI

/// Lockin Plus: your Lockling in a crown, what Plus adds, three plans and one button.
///
/// Short on purpose: five lines of features, no paragraphs. Present it as a sheet; `onClose` runs
/// when the person closes it, and after a purchase or restore that unlocks Plus.
public struct PaywallView: View {
    @ObservedObject private var store: PlusStore
    private let avatar: AvatarCode
    private let onClose: () -> Void

    @State private var plan: PlusPlan = .yearly
    @State private var isWorking = false
    @State private var failure: PlusStoreError?
    @State private var showsFailure = false
    @State private var showsNothingToRestore = false
    @Environment(\.purchase) private var purchaseAction

    /// The Terms of Use and Privacy Policy pages (`<web host>/terms`, `/privacy`; M9), which App
    /// Review wants linked from the paywall (Guideline 3.1.2). Nil in a build with no web or API
    /// host (the simulator's default): the links hide rather than point anywhere made up.
    let termsURL: URL?
    let privacyURL: URL?

    /// `configuration` decides where Terms and Privacy go; the build's own unless a preview or a
    /// snapshot says otherwise.
    public init(store: PlusStore, avatar: AvatarCode, configuration: AppConfiguration = .main, onClose: @escaping () -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.avatar = avatar
        self.onClose = onClose
        termsURL = configuration.webURL(.terms)
        privacyURL = configuration.webURL(.privacy)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.xl) {
                header
                features
            }
            .padding(.horizontal, LKSpacing.gutter)
            .padding(.top, LKSpacing.xl)
            .padding(.bottom, LKSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LKColor.groupedBackground)
        .modifier(BottomBar(bar: purchaseBar))
        .overlay(alignment: .topTrailing) {
            CloseButton(action: onClose)
                .padding(.top, LKSpacing.s)
                .padding(.trailing, LKSpacing.l)
        }
        .sensoryFeedback(.selection, trigger: plan)
        .alert("Purchase didn't go through", isPresented: $showsFailure, presenting: failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.errorDescription ?? "")
        }
        .alert("Nothing to restore", isPresented: $showsNothingToRestore) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This Apple Account hasn't bought Lockin Plus.")
        }
        .task { [store] in
            // Again here in case the launch-time load was offline.
            await store.load()
        }
        .onAppear {
            store.analytics.track(.paywallShown)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: LKSpacing.s) {
            CreatureView(avatar: Self.crowned(avatar), pose: .celebrating, size: 110)
                .frame(width: 124, height: 124)
                .background {
                    Circle()
                        .fill(RadialGradient(
                            colors: [LKColor.tint.opacity(0.35), LKColor.tint.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        ))
                        .frame(width: 200, height: 200)
                }
                .padding(.bottom, LKSpacing.s)
                .accessibilityHidden(true)
            Text("Lockin Plus")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(store.isPlus ? "You're on Plus. Thanks for backing Lockin." : "More squad, more style, more focus.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            ForEach(PlusFeature.all) { feature in
                HStack(spacing: LKSpacing.m) {
                    LKIconTile(systemName: feature.symbol, color: feature.color, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(feature.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feature.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .lkCard()
    }

    /// The three plans side by side, pinned above the button so they're never scrolled away.
    private var plans: some View {
        HStack(spacing: LKSpacing.s) {
            ForEach(PlusPlan.allCases) { option in
                PlanCard(
                    plan: option,
                    price: store.displayPrice(for: option),
                    detail: detail(for: option),
                    badge: badge(for: option),
                    isSelected: plan == option
                ) {
                    plan = option
                }
            }
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: LKSpacing.m) {
            if store.isPlus {
                Button(action: onClose) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .lkProminentButton()
                .controlSize(.large)
            } else {
                plans
                Button(action: buy) {
                    ZStack {
                        Text(plan.callToAction(trialAvailable: store.isTrialAvailable))
                            .opacity(isWorking ? 0 : 1)
                        if isWorking {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .lkProminentButton()
                .controlSize(.large)
                .disabled(isWorking)

                Text(plan.disclosure(price: store.displayPrice(for: plan), trialAvailable: store.isTrialAvailable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: LKSpacing.s) {
                Button("Restore", action: restore)
                    .disabled(isWorking)
                if let termsURL {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Link("Terms", destination: termsURL)
                }
                if let privacyURL {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Link("Privacy", destination: privacyURL)
                }
            }
            .font(.footnote)
        }
        .padding(.horizontal, LKSpacing.gutter)
        .padding(.top, LKSpacing.m)
        .padding(.bottom, LKSpacing.s)
    }

    private func detail(for option: PlusPlan) -> String? {
        switch option {
        case .yearly: "\(store.monthlyEquivalentOfYearly())/mo"
        case .monthly: nil
        case .lifetime: "Pay once"
        }
    }

    private func badge(for option: PlusPlan) -> String? {
        guard option == .yearly else { return nil }
        return store.isTrialAvailable ? "\(PlusPlan.trialDays) days free" : "Best value"
    }

    // MARK: - Actions

    private func buy() {
        guard !isWorking else { return }
        isWorking = true
        let chosen = plan
        Task {
            defer { isWorking = false }
            do {
                if try await store.purchase(chosen, using: purchaseAction) {
                    onClose()
                }
            } catch {
                failure = error as? PlusStoreError ?? .failed
                showsFailure = true
            }
        }
    }

    private func restore() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await store.restore()
            isWorking = false
            if store.isPlus {
                onClose()
            } else {
                showsNothingToRestore = true
            }
        }
    }

    // MARK: - The crown

    /// The avatar wearing the Plus crown: the Plus hat named "crown", or the first Plus hat.
    static func crowned(_ avatar: AvatarCode) -> AvatarCode {
        var crowned = avatar
        if let crown = crownHatID(in: CreatureCatalogue.hats) {
            crowned.hat = crown
        }
        return crowned
    }

    nonisolated static func crownHatID(in hats: [CreatureOption]) -> Int? {
        let plusHats = hats.filter(\.isPlus)
        let crown = plusHats.first { $0.name.localizedCaseInsensitiveContains("crown") } ?? plusHats.first
        return crown?.id
    }
}

/// One line of what Plus adds.
struct PlusFeature: Identifiable, Sendable {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var id: String { title }

    static let all: [PlusFeature] = [
        PlusFeature(symbol: "person.3.fill", color: .indigo, title: "Bigger squads", detail: "Up to 6 friends, in 3 squads"),
        PlusFeature(symbol: "sparkles", color: .pink, title: "Every cosmetic", detail: "Plus a new drop every month"),
        PlusFeature(symbol: "hourglass", color: .purple, title: "Deep Focus", detail: "Block distracting apps"),
        PlusFeature(symbol: "pawprint.fill", color: .orange, title: "Squad Boost", detail: "Unlock pet gear for your whole squad"),
        PlusFeature(symbol: "snowflake", color: .cyan, title: "Streak freezes", detail: "2 a month, for the days life happens"),
    ]
}

/// A plan to pick, as one of three cards in a row: the badge (if any), the name, the price and a
/// short line under it. The selected card wears the tint.
private struct PlanCard: View {
    let plan: PlusPlan
    let price: String
    let detail: String?
    let badge: String?
    let isSelected: Bool
    let select: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LKRadius.medium, style: .continuous)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: LKSpacing.xxs) {
                // Every card keeps the badge's height, so the three line up.
                Text(badge ?? " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, LKSpacing.s)
                    .padding(.vertical, 2)
                    .background(badge == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.tint), in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(plan.title)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, LKSpacing.xxs)
                Text(price)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail ?? plan.period ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, LKSpacing.s)
            .padding(.horizontal, LKSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(LKColor.secondaryGroupedBackground, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(LKColor.separator), lineWidth: isSelected ? 2 : 0.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Top trailing: Liquid Glass on iOS 26, the classic filled circle before.
private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("Close")
        } else {
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}

/// The purchase button pinned under the scrolling content: a scroll-edge bar on iOS 26, a bar
/// material before.
private struct BottomBar<Bar: View>: ViewModifier {
    let bar: Bar

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom) {
                bar
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                bar.background(Material.bar)
            }
        }
    }
}
