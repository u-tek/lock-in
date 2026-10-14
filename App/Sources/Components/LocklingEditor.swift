import Creature
import DesignSystem
import Model
import SwiftUI

/// One part of a Lockling the editor changes, in the avatar code's order.
enum LocklingPart: String, CaseIterable, Identifiable {
    case body
    case colour
    case eyes
    case hat

    var id: Self { self }

    var title: String {
        switch self {
        case .body: "Body"
        case .colour: "Colour"
        case .eyes: "Eyes"
        case .hat: "Hat"
        }
    }

    var symbol: String {
        switch self {
        case .body: "lock.fill"
        case .colour: "paintpalette.fill"
        case .eyes: "eye.fill"
        case .hat: "graduationcap.fill"
        }
    }

    var options: [CreatureOption] {
        switch self {
        case .body: CreatureCatalogue.bodies
        case .colour: CreatureCatalogue.colours
        case .eyes: CreatureCatalogue.eyes
        case .hat: CreatureCatalogue.hats
        }
    }

    func selection(in avatar: AvatarCode) -> Int {
        switch self {
        case .body: avatar.body
        case .colour: avatar.colour
        case .eyes: avatar.eyes
        case .hat: avatar.hat
        }
    }

    func applying(_ id: Int, to avatar: AvatarCode) -> AvatarCode {
        var changed = avatar
        switch self {
        case .body: changed.body = id
        case .colour: changed.colour = id
        case .eyes: changed.eyes = id
        case .hat: changed.hat = id
        }
        return changed
    }
}

/// The Lockling maker: the creature, big, then a row of parts and the choices for the one picked.
/// Used by onboarding and by Settings › Edit Lockling.
struct LocklingEditor: View {
    @Binding var avatar: AvatarCode
    let isPlus: Bool
    /// A Plus-only choice was tapped without Plus: show the paywall.
    let onLockedOption: () -> Void
    var heroSize: CGFloat = 180

    @State private var part: LocklingPart = .body

    var body: some View {
        VStack(spacing: LKSpacing.xl) {
            LocklingHero(avatar: avatar, pose: .idle, size: heroSize)
                .bump(on: avatar)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your Lockling")

            VStack(spacing: LKSpacing.l) {
                PartTabs(selection: $part)
                    .padding(.horizontal, LKSpacing.xl)
                OptionStrip(part: part, avatar: $avatar, isPlus: isPlus, onLockedOption: onLockedOption)
            }
        }
        .sensoryFeedback(.selection, trigger: avatar)
        .sensoryFeedback(.selection, trigger: part)
    }
}

/// Body, Colour, Eyes, Hat: a segmented row with a symbol over each name.
private struct PartTabs: View {
    @Binding var selection: LocklingPart
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LocklingPart.allCases) { part in
                let isSelected = part == selection
                Button {
                    withAnimation(.snappy) { selection = part }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: part.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 20)
                        Text(part.title)
                            .font(LKFont.caption.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(LKColor.textSecondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LKSpacing.s)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(LKColor.tint.opacity(0.14))
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(part.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(LKSpacing.xs)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// The choices for one part, side by side, scrolling sideways. Each shows the Lockling wearing it
/// (or the colour itself), with a crown on the Plus ones.
private struct OptionStrip: View {
    let part: LocklingPart
    @Binding var avatar: AvatarCode
    let isPlus: Bool
    let onLockedOption: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(part.options) { option in
                        let isSelected = part.selection(in: avatar) == option.id
                        let isLocked = option.isPlus && !isPlus
                        Button {
                            if isLocked {
                                onLockedOption()
                            } else {
                                withAnimation(.snappy) {
                                    avatar = part.applying(option.id, to: avatar)
                                }
                            }
                        } label: {
                            OptionChip(
                                part: part,
                                option: option,
                                preview: part.applying(option.id, to: avatar),
                                isSelected: isSelected,
                                showsCrown: option.isPlus
                            )
                        }
                        .buttonStyle(TileButtonStyle())
                        .id(option.id)
                        .accessibilityLabel(option.name)
                        .accessibilityValue(isLocked ? Text("Lockin Plus") : Text(""))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, LKSpacing.xl)
                // Room for the crowns, which sit over the chips' corners.
                .padding(.vertical, LKSpacing.s)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onAppear {
                // The current choice in view, even when it's far along the row.
                proxy.scrollTo(part.selection(in: avatar), anchor: .center)
            }
        }
        // A fresh row for each part, so it starts at that part's current choice.
        .id(part)
        .transition(.opacity)
    }
}

private struct OptionChip: View {
    let part: LocklingPart
    let option: CreatureOption
    /// The Lockling with this option on.
    let preview: AvatarCode
    let isSelected: Bool
    let showsCrown: Bool

    private static let side: CGFloat = 68
    private static let corner: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        Group {
            if part == .colour {
                Circle()
                    .fill(CreatureCatalogue.colour(option.id).gradient)
                    .frame(width: 40, height: 40)
            } else {
                CreatureView(avatar: preview, pose: .idle, size: 46)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(isSelected ? AnyShapeStyle(LKColor.tint.opacity(0.14)) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)), in: shape)
        .overlay {
            if isSelected {
                shape.strokeBorder(.tint, lineWidth: 2.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsCrown {
                PlusBadge()
                    .offset(x: 5, y: -5)
            }
        }
        .contentShape(shape)
    }
}
