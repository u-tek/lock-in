import API
import DesignSystem
import Social
import SwiftUI

/// Who to lock in with: "Solo", or one of your squads. A squad whose room is open shows a live
/// dot and how many are in it. Long-press a squad to manage it.
///
/// Centred when the chips fit, scrolling sideways when they don't (three squads on an SE).
struct SquadPicker: View {
    let squads: [Squad]
    @ObservedObject var rooms: SquadRooms
    /// The chosen squad's id; nil for solo.
    @Binding var selection: String?
    let onManage: (Squad) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal) {
                chips
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, LKSpacing.xl, for: .scrollContent)
            // Edge to edge, so chips scroll under the screen's margins rather than stopping at
            // them.
            .padding(.horizontal, -LKSpacing.xl)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var chips: some View {
        HStack(spacing: LKSpacing.s) {
            SquadChip(isSelected: selection == nil) {
                choose(nil)
            } label: {
                Label("Solo", systemImage: "person.fill")
            }
            ForEach(squads) { squad in
                SquadChip(isSelected: selection == squad.id) {
                    choose(squad.id)
                } label: {
                    SquadChipLabel(squad: squad, count: rooms.count(for: squad), isSelected: selection == squad.id)
                }
                .contextMenu {
                    Button {
                        onManage(squad)
                    } label: {
                        Label("Manage squad", systemImage: "person.3")
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func choose(_ id: String?) {
        withAnimation(.snappy) {
            selection = id
        }
    }
}

/// A squad's name, and when its room is open, a live dot and "3 locked in".
private struct SquadChipLabel: View {
    let squad: Squad
    let count: Int?
    let isSelected: Bool

    private var isLive: Bool {
        squad.openSessionId != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            if isLive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
            }
            Text(squad.name)
            if isLive, let count, count > 0 {
                Text("\(count) locked in")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(squad.name))
        .accessibilityValue(liveDescription)
    }

    private var liveDescription: Text {
        guard isLive else { return Text("") }
        if let count, count > 0 {
            return Text("\(count) locked in now")
        }
        return Text("Locked in now")
    }
}

/// A capsule that's filled with the tint when chosen, like the duration tiles below it.
private struct SquadChip<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let label: Content

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(LKFont.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(
                    isSelected ? AnyShapeStyle(LKColor.tint) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
