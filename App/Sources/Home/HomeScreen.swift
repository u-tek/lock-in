import Creature
import DesignSystem
import Model
import Paywall
import SessionEngine
import SwiftUI

/// Home: your Lockling, how long, and one button. Coins, Plus and Settings sit in the bar; squads
/// are a quiet row at the bottom until they arrive (M3).
struct HomeScreen: View {
    enum Sheet: String, Identifiable {
        case paywall
        case settings
        case squads
        case customLength

        var id: String { rawValue }
    }

    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore

    @State private var minutes: Int
    @State private var sheet: Sheet?
    @State private var pokes = 0
    @State private var lockIns = 0

    init(engine: SessionEngine, plus: PlusStore, minutes: Int = SessionPreset.twentyFive.minutes) {
        self.engine = engine
        self.plus = plus
        _minutes = State(initialValue: minutes)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: LKSpacing.s)
                    hero(height: proxy.size.height)
                    StatChips(stats: engine.stats)
                        .padding(.top, LKSpacing.l)
                    Spacer(minLength: LKSpacing.l)
                    DurationPicker(minutes: $minutes, isPlus: plus.isPlus) {
                        sheet = plus.isPlus ? .customLength : .paywall
                    }
                    lockInButton
                        .padding(.top, LKSpacing.l)
                    friendsButton
                        .padding(.top, LKSpacing.xs)
                }
                .padding(.horizontal, LKSpacing.xl)
                .padding(.bottom, LKSpacing.xs)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .paywall:
                PaywallView(store: plus, avatar: engine.avatar) {
                    self.sheet = nil
                }
            case .settings:
                SettingsScreen(engine: engine, plus: plus) {
                    self.sheet = nil
                }
            case .squads:
                // The made-up friends' timers count from when it opens.
                SquadsTeaser(now: Date())
            case .customLength:
                CustomLengthSheet(minutes: $minutes)
            }
        }
    }

    /// The Lockling, as large as the screen allows: 200 points on most phones, less on an SE.
    private func hero(height: CGFloat) -> some View {
        LocklingHero(
            avatar: engine.avatar,
            pose: .idle,
            size: min(200, max(120, height * 0.3)),
            backdrop: .halo
        )
        .bump(on: pokes)
        .onTapGesture { pokes += 1 }
        .sensoryFeedback(.impact(weight: .light), trigger: pokes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Lockling")
    }

    private var lockInButton: some View {
        Button {
            lockIns += 1
            engine.start(minutes: minutes)
        } label: {
            Label("Lock in", systemImage: "lock.fill")
                .font(LKFont.headline)
                .frame(maxWidth: .infinity)
        }
        .lkProminentButton()
        .controlSize(.large)
        .sensoryFeedback(.impact(weight: .medium), trigger: lockIns)
    }

    private var friendsButton: some View {
        Button {
            sheet = .squads
        } label: {
            Label("Lock in with friends", systemImage: "person.2.fill")
                .font(LKFont.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            CoinCount(coins: engine.stats.coins)
                .toolbarPill()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !plus.isPlus {
                Button {
                    sheet = .paywall
                } label: {
                    Label {
                        Text("Plus")
                    } icon: {
                        Image(systemName: LockinSymbol.plus)
                            .foregroundStyle(LockinColour.plus)
                    }
                    .labelStyle(.titleAndIcon)
                    .font(LKFont.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Lockin Plus")
            }
            Button("Settings", systemImage: "gearshape") {
                sheet = .settings
            }
        }
    }
}

/// Today's minutes and the streak, as two small capsules.
private struct StatChips: View {
    let stats: FocusStats

    var body: some View {
        HStack(spacing: LKSpacing.s) {
            StatChip(symbol: "clock.fill", colour: LKColor.tint, text: "\(stats.todayMinutes) min today")
            StatChip(symbol: "flame.fill", colour: .orange, text: streak)
        }
    }

    private var streak: String {
        switch stats.streakDays {
        case 0: "No streak yet"
        case 1: "1 day"
        default: "\(stats.streakDays) days"
        }
    }
}

private struct StatChip: View {
    let symbol: String
    let colour: Color
    let text: String

    var body: some View {
        Label {
            Text(text)
                .monospacedDigit()
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(colour)
        }
        .font(LKFont.subheadline.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, LKSpacing.m)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

/// 25, 50 and 90 minutes, and a custom length (Lockin Plus): four big tiles.
private struct DurationPicker: View {
    @Binding var minutes: Int
    let isPlus: Bool
    let onCustom: () -> Void

    private let presets = SessionPreset.standard.map(\.minutes)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.self) { value in
                DurationTile(isSelected: minutes == value) {
                    withAnimation(.snappy) { minutes = value }
                } content: {
                    Text(value, format: .number)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("min")
                        .font(LKFont.caption.weight(.medium))
                }
                .accessibilityLabel("\(value) minutes")
            }
            customTile
        }
        .sensoryFeedback(.selection, trigger: minutes)
    }

    private var customTile: some View {
        let isCustom = !presets.contains(minutes)
        return DurationTile(isSelected: isCustom, action: onCustom) {
            if isCustom {
                Text(minutes, format: .number)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("min")
                    .font(LKFont.caption.weight(.medium))
            } else {
                Image(systemName: isPlus ? "timer" : LockinSymbol.plus)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isPlus ? AnyShapeStyle(.primary) : AnyShapeStyle(LockinColour.plus))
                    .frame(height: 28)
                Text("Custom")
                    .font(LKFont.caption.weight(.medium))
            }
        }
        .accessibilityLabel(isCustom ? "\(minutes) minutes" : "Custom length")
        .accessibilityValue(isPlus ? Text("") : Text("Lockin Plus"))
    }
}

private struct DurationTile<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                content
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                isSelected ? AnyShapeStyle(LKColor.tint) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lockin Plus: any length from 5 minutes to the 4-hour cap.
private struct CustomLengthSheet: View {
    @Binding var minutes: Int
    @State private var draft: Int
    @Environment(\.dismiss) private var dismiss

    private static let choices = Array(stride(from: 5, through: SessionPreset.customRange.upperBound, by: 5))

    init(minutes: Binding<Int>) {
        _minutes = minutes
        _draft = State(initialValue: minutes.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Picker("Minutes", selection: $draft) {
                ForEach(Self.choices, id: \.self) { value in
                    Text("\(value) min").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle("Custom length")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        minutes = draft
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
