import DesignSystem
import SwiftUI

/// DesignSystem's catalogue: every colour, the type ramp, spacing and radii, and the shared
/// components (design/SYSTEM.md). Snapshot route `lab.tokens`; each part is also
/// `lab.tokens.<part>`.
///
/// An inset-grouped list like the rest of the app. Colours are resolved on this phone, so the
/// page shows what the system actually draws rather than numbers copied from somewhere.
struct DesignTokensScreen: View {
    enum Panel: String, CaseIterable, Identifiable {
        case colours
        case type
        case metrics
        case components

        var id: String { rawValue }
    }

    private let panels: [Panel]

    init(panels: [Panel] = Panel.allCases) {
        self.panels = panels
    }

    var body: some View {
        List {
            ForEach(panels) { panel in
                switch panel {
                case .colours: ColourSections()
                case .type: TypeSection()
                case .metrics: MetricsSections()
                case .components: ComponentSections()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Design tokens")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Colours

private struct ColourSections: View {
    var body: some View {
        ForEach(LKColorCatalogue.groups) { group in
            Section {
                ForEach(group.tokens) { token in
                    ColourRow(token: token)
                }
            } header: {
                Text(group.name)
            } footer: {
                // Once, under the first group, rather than under every one.
                if group == LKColorCatalogue.groups.first {
                    Text("System colours only, resolved on this phone. Each swatch is light on the left and dark on the right; a percentage is the colour's opacity.")
                }
            }
        }
    }
}

private struct ColourRow: View {
    let token: LKColorToken

    var body: some View {
        HStack(spacing: LKSpacing.m) {
            Swatch(token: token)
            // Names like secondaryGroupedBackground have nowhere to wrap, so they shrink to fit.
            VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                Text(token.name)
                Text(token.uiKitName)
                    .font(LKFont.footnote)
                    .foregroundStyle(LKColor.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: LKSpacing.s)
            VStack(alignment: .trailing, spacing: LKSpacing.xxs) {
                Text(token.hexString(in: .light))
                if !token.isFixed {
                    Text(token.hexString(in: .dark))
                }
            }
            .font(LKFont.caption.monospaced())
            .foregroundStyle(LKColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The token in both appearances side by side, whatever the screen's own. A translucent colour
/// (the separator, the label colours) is shown over the card colour of the same appearance, as a
/// row would draw it.
private struct Swatch: View {
    let token: LKColorToken

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LKRadius.small, style: .continuous)
        HStack(spacing: 0) {
            half(.light)
            if !token.isFixed {
                half(.dark)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(shape)
        .overlay {
            // The light half of a white token would vanish into a white row without an edge.
            shape.strokeBorder(LKColor.separator, lineWidth: 0.5)
        }
    }

    private func half(_ scheme: ColorScheme) -> some View {
        token.color(in: scheme)
            .background(LKColorCatalogue.secondaryGroupedBackground.color(in: scheme))
    }
}

// MARK: - Type

private struct TypeSection: View {
    var body: some View {
        Section {
            ForEach(LKTypeStyle.allCases) { style in
                VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                    Text(style.sample)
                        .font(style.font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("\(style.name) · \(style.summary)")
                        .font(LKFont.footnote)
                        .foregroundStyle(LKColor.textSecondary)
                }
                .padding(.vertical, LKSpacing.xxs)
            }
        } header: {
            Text("Type")
        } footer: {
            Text("SF Pro through Dynamic Type, so text follows the reader's size. Timers have monospaced digits; only the in-app and StandBy ones are fixed sizes.")
        }
    }
}

// MARK: - Spacing and radii

private struct MetricsSections: View {
    var body: some View {
        Section {
            ForEach(LKSpacing.all) { metric in
                LabeledContent {
                    HStack(spacing: LKSpacing.m) {
                        Text(verbatim: "\(Int(metric.value)) pt")
                            .monospacedDigit()
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(.tint)
                            .frame(width: metric.value, height: 12)
                            // The widest step's width, so every bar starts in the same place.
                            .frame(width: LKSpacing.xxxl, alignment: .leading)
                    }
                } label: {
                    Text(metric.name)
                }
            }
        } header: {
            Text("Spacing")
        } footer: {
            Text("A 4-point grid, for layouts drawn by hand. Lists, forms and bars bring their own margins.")
        }

        Section {
            HStack(alignment: .bottom, spacing: LKSpacing.l) {
                ForEach(LKRadius.all) { metric in
                    VStack(spacing: LKSpacing.xs) {
                        RoundedRectangle(cornerRadius: metric.value, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 64, height: 64)
                        Text(verbatim: "\(metric.name) \(Int(metric.value))")
                            .font(LKFont.caption)
                            .foregroundStyle(LKColor.textSecondary)
                    }
                }
            }
            .padding(.vertical, LKSpacing.s)
        } header: {
            Text("Corner radii")
        } footer: {
            Text("Always continuous. Let containers choose where they can; these are for shapes drawn by hand.")
        }
    }
}

// MARK: - Components

private struct ComponentSections: View {
    var body: some View {
        Section {
            Button {} label: {
                Text("Prominent")
                    .frame(maxWidth: .infinity)
            }
            .lkProminentButton()
            .controlSize(.large)
            Button {} label: {
                Text("Secondary")
                    .frame(maxWidth: .infinity)
            }
            .lkSecondaryButton()
            .controlSize(.large)
            HStack(spacing: LKSpacing.s) {
                Button("Destructive", role: .destructive) {}
                    .lkSecondaryButton()
                Button("Disabled") {}
                    .lkProminentButton()
                    .disabled(true)
            }
        } header: {
            Text("Buttons")
        } footer: {
            Text("The system's styles: Liquid Glass on iOS 26, bordered before. Large for a screen's main action. Specimens: these do nothing.")
        }

        Section {
            ForEach(LKMemberTone.allCases) { tone in
                Label {
                    Text(tone.title)
                } icon: {
                    LKIconTile(systemName: tone.symbolName, color: tone.color)
                }
            }
        } header: {
            Text("Icon tiles")
        } footer: {
            Text("Settings-style row icons, here in the six member states' colours and symbols.")
        }

        Section {
            CardSpecimen(title: "Material card", detail: "Floats over other content, which shows through: the regular material.")
                .lkMaterialCard()
                .activityStageRow(.wallpaper)
            CardSpecimen(title: "Card", detail: "The grouped card colour, for the few things that can't be a list row.")
                .lkCard()
                .padding(LKSpacing.l)
                .listRowInsets(EdgeInsets())
                // The card's own setting, so it shows as it would on a screen of cards.
                .listRowBackground(LKColor.groupedBackground)
        } header: {
            Text("Cards")
        } footer: {
            Text("Continuous 26-point corners, no border, no shadow.")
        }
    }
}

private struct CardSpecimen: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xxs) {
            Text(title)
                .font(LKFont.headline)
            Text(detail)
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textSecondary)
        }
    }
}
