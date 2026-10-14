import API
import Creature
import DesignSystem
import Model
import Paywall
import Social
import SwiftUI

/// The coin shop (docs/milestones/M5.md): Lockling items by part, each shown on your own Lockling,
/// priced in coins. A sheet from the coin count on Home.
///
/// Tapping something you own puts it on; something for sale asks first, then buys it and puts it
/// on; a Plus item without Plus opens the paywall (SPEC.md §2, paywall moment 3). What you can't
/// afford yet is dimmed, with how many coins are still to earn.
struct ShopScreen: View {
    @ObservedObject var shop: ShopStore
    /// The balance signed in is the account's.
    @ObservedObject var account: AccountStore
    @ObservedObject var plus: PlusStore
    /// Your Lockling, which wears what you pick.
    @Binding var avatar: AvatarCode
    let onDone: () -> Void

    @State private var confirming: ShopItem?
    /// Just bought: a note at the bottom for a moment.
    @State private var bought: ShopItem?
    @State private var showsPaywall = false
    @State private var failure: String?

    /// The parts in the order the shop shows them.
    static let parts: [ShopPart] = [.hat, .colour, .eyes, .body]

    /// - Parameter bought: an item just bought, to show its note (snapshots).
    init(
        shop: ShopStore,
        account: AccountStore,
        plus: PlusStore,
        avatar: Binding<AvatarCode>,
        bought: ShopItem? = nil,
        onDone: @escaping () -> Void
    ) {
        self.shop = shop
        self.account = account
        self.plus = plus
        _avatar = avatar
        _bought = State(initialValue: bought)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.xl) {
                    header
                    ForEach(Self.parts) { part in
                        section(part)
                    }
                }
                .padding(.horizontal, LKSpacing.gutter)
                .padding(.bottom, LKSpacing.xxxl)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .overlay(alignment: .bottom) {
                if let bought {
                    BoughtNote(item: bought)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .confirmationDialog(
            Text(verbatim: confirming.map { "Buy \($0.name)?" } ?? ""),
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirming
        ) { item in
            Button("Buy for \(item.price) coins") {
                buy(item)
            }
            Button("Cancel", role: .cancel) {}
        }
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: avatar)
        .errorAlert("Couldn't buy that", message: $failure)
        .sensoryFeedback(.success, trigger: bought)
        .task {
            await shop.refresh()
        }
        .task(id: bought) {
            // The note goes after a moment; snapshots keep it.
            guard bought != nil, SnapshotMode.current == nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(LKMotion.settle) {
                bought = nil
            }
        }
    }

    // MARK: - Pieces

    /// Your Lockling in what it's wearing, and your coins.
    private var header: some View {
        VStack(spacing: LKSpacing.m) {
            LocklingHero(avatar: avatar, pose: .idle, size: 96, backdrop: .halo)
                .bump(on: avatar)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your Lockling")
            CoinCount(coins: shop.coins)
                .font(LKFont.headline)
                .padding(.horizontal, LKSpacing.l)
                .frame(minHeight: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .padding(.top, LKSpacing.s)
    }

    /// One part's items, three to a row.
    private func section(_ part: ShopPart) -> some View {
        let items = ShopCatalogue.items(for: part)
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        return VStack(alignment: .leading, spacing: LKSpacing.s) {
            Text(part.shopTitle)
                .font(LKFont.headline)
                .accessibilityAddTraits(.isHeader)
            Grid(horizontalSpacing: LKSpacing.m, verticalSpacing: LKSpacing.m) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index]) { item in
                            tile(item)
                        }
                        // Short rows keep their tiles the width of a full row's.
                        ForEach(rows[index].count..<3, id: \.self) { _ in
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private func tile(_ item: ShopItem) -> some View {
        let state = state(of: item)
        return Button {
            tap(item, state)
        } label: {
            ItemTile(item: item, preview: item.applied(to: avatar), state: state)
        }
        .buttonStyle(TileButtonStyle())
        .disabled(state.isShort || shop.buying != nil)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: state.spoken(price: item.price)))
    }

    private func state(of item: ShopItem) -> ItemTile.State {
        if item.isWorn(by: avatar) {
            return .wearing
        }
        if item.plus {
            return plus.isPlus ? .owned : .plus
        }
        if shop.owns(item) {
            return .owned
        }
        if shop.buying == item.id {
            return .buying
        }
        return .forSale(shortfall: shop.shortfall(for: item))
    }

    // MARK: - Actions

    private func tap(_ item: ShopItem, _ state: ItemTile.State) {
        switch state {
        case .wearing, .buying:
            return
        case .owned:
            withAnimation(LKMotion.press) {
                avatar = item.applied(to: avatar)
            }
        case .plus:
            showsPaywall = true
        case .forSale(let shortfall):
            guard shortfall == 0 else { return }
            confirming = item
        }
    }

    private func buy(_ item: ShopItem) {
        Task {
            do {
                try await shop.buy(item)
                withAnimation(LKMotion.celebrate) {
                    avatar = item.applied(to: avatar)
                    bought = item
                }
            } catch is CancellationError {
                return
            } catch let error as APIError where error.code == .plusRequired {
                showsPaywall = true
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
            }
        }
    }
}

/// One item: your Lockling wearing it, its name, and its price, or that it's yours.
private struct ItemTile: View {
    enum State: Equatable {
        /// On your Lockling now.
        case wearing
        /// Yours: tap to put it on.
        case owned
        /// A Plus item, without Plus.
        case plus
        /// Being bought.
        case buying
        /// For sale; `shortfall` coins still to earn (0: affordable).
        case forSale(shortfall: Int)

        var isShort: Bool {
            if case .forSale(let shortfall) = self { shortfall > 0 } else { false }
        }

        /// For VoiceOver, after the item's name.
        func spoken(price: Int) -> String {
            switch self {
            case .wearing: "Wearing"
            case .owned: "Owned"
            case .plus: "Lockin Plus"
            case .buying: "Buying"
            case .forSale(let shortfall):
                shortfall > 0 ? "\(price) coins, \(shortfall) more to earn" : "\(price) coins"
            }
        }
    }

    let item: ShopItem
    let preview: AvatarCode
    let state: State

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LKRadius.medium, style: .continuous)
        VStack(spacing: LKSpacing.xs) {
            CreatureView(avatar: preview, pose: .idle, size: 52)
                .frame(height: 58)
            Text(item.name)
                .font(LKFont.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            status
                .font(LKFont.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
            if case .forSale(let shortfall) = state, shortfall > 0 {
                Text("\(shortfall) more")
                    .font(LKFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, LKSpacing.m)
        .padding(.horizontal, LKSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        .overlay {
            if state == .wearing {
                shape.strokeBorder(.tint, lineWidth: 2.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.plus {
                PlusBadge()
                    .padding(LKSpacing.s)
            }
        }
        .opacity(state.isShort ? 0.55 : 1)
        .contentShape(shape)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .wearing:
            Label("Wearing", systemImage: "checkmark")
                .foregroundStyle(.tint)
        case .owned:
            Label("Yours", systemImage: "checkmark.circle.fill")
                .foregroundStyle(LKColor.done)
        case .plus:
            Text("Plus")
                .foregroundStyle(LockinColour.plus)
        case .buying:
            ProgressView()
                .controlSize(.small)
        case .forSale:
            HStack(spacing: LKSpacing.xxs + 1) {
                Image(systemName: LockinSymbol.coin)
                    .foregroundStyle(LockinColour.coin)
                Text(item.price, format: .number)
                    .foregroundStyle(.primary)
            }
        }
    }
}

/// "Cap is yours", for a moment after buying it.
private struct BoughtNote: View {
    let item: ShopItem

    var body: some View {
        Label {
            Text("\(item.name) is yours")
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LKColor.done)
        }
        .font(LKFont.subheadline.weight(.semibold))
        .padding(.horizontal, LKSpacing.l)
        .padding(.vertical, LKSpacing.m)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, LKSpacing.l)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Names

extension ShopPart {
    /// The shop's section titles.
    var shopTitle: String {
        switch self {
        case .hat: "Hats"
        case .colour: "Colours"
        case .eyes: "Eyes"
        case .body: "Bodies"
        }
    }

    /// The Lockling's choices for this part, as the Creature module draws them.
    var creatureOptions: [CreatureOption] {
        switch self {
        case .body: CreatureCatalogue.bodies
        case .colour: CreatureCatalogue.colours
        case .eyes: CreatureCatalogue.eyes
        case .hat: CreatureCatalogue.hats
        }
    }
}

extension ShopItem {
    /// The option's name: "Beanie", "Teal".
    var name: String {
        part.creatureOptions.first { $0.id == option }?.name ?? "\(part.shopTitle) \(option)"
    }
}
