import DesignSystem
import SwiftUI

/// DesignSystem's catalogue: every colour token, the type ramp, spacing and radii, and the shared
/// components. Snapshot route `lab.tokens`; each part is also `lab.tokens.<part>`.
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
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.xxl) {
                ForEach(panels) { panel in
                    switch panel {
                    case .colours: ColourPanel()
                    case .type: TypePanel()
                    case .metrics: MetricsPanel()
                    case .components: ComponentsPanel()
                    }
                }
            }
            .padding(.horizontal, LKSpacing.gutter)
            .padding(.top, LKSpacing.l)
            .padding(.bottom, LKSpacing.xxxl)
        }
        .lkScreenBackground()
        .navigationTitle("Design tokens")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Colours

private struct ColourPanel: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: LKSpacing.s, alignment: .top), count: 4)

    var body: some View {
        TokenPanel("Colour", detail: "Each swatch: light on the left, dark on the right") {
            ForEach(LKPalette.groups) { group in
                VStack(alignment: .leading, spacing: LKSpacing.s) {
                    LKSectionHeader(group.name)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: LKSpacing.m) {
                        ForEach(group.tokens) { token in
                            Swatch(token: token)
                        }
                    }
                }
            }
        }
    }
}

private struct Swatch: View {
    let token: LKColorToken

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LKRadius.small, style: .continuous)
        VStack(alignment: .leading, spacing: LKSpacing.xxs) {
            // Both values side by side, whatever the screen's appearance.
            HStack(spacing: 0) {
                Color(rgb: token.light)
                if !token.isFixed {
                    Color(rgb: token.dark)
                }
            }
            .frame(height: 36)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LKColor.separator, lineWidth: 1)
            }
            .padding(.bottom, LKSpacing.xxs)
            Text(token.name)
                .font(LKFont.caption.weight(.semibold))
                .foregroundStyle(LKColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(token.light.hexString)
                .font(Self.hexFont)
                .foregroundStyle(LKColor.textSecondary)
            if !token.isFixed {
                Text(token.dark.hexString)
                    .font(Self.hexFont)
                    .foregroundStyle(LKColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static let hexFont = Font.system(size: 10, weight: .medium, design: .monospaced)
}

// MARK: - Type

private struct TypePanel: View {
    var body: some View {
        TokenPanel("Type", detail: "SF Rounded; timers fixed with monospaced digits") {
            ForEach(LKTypeStyle.allCases) { style in
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.sample)
                        .lkType(style)
                        .foregroundStyle(LKColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("\(style.name) · \(style.summary)")
                        .font(LKFont.caption)
                        .foregroundStyle(LKColor.textSecondary)
                }
            }
        }
    }
}

// MARK: - Spacing and radii

private struct MetricsPanel: View {
    var body: some View {
        TokenPanel("Spacing and radii", detail: "Points; corners always continuous") {
            VStack(alignment: .leading, spacing: LKSpacing.s) {
                ForEach(LKSpacing.all) { metric in
                    HStack(spacing: LKSpacing.m) {
                        MetricLabel(metric: metric)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(LKColor.accent)
                            .frame(width: metric.value, height: 12)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: LKSpacing.l) {
                ForEach(LKRadius.all) { metric in
                    VStack(spacing: LKSpacing.xs) {
                        RoundedRectangle(cornerRadius: metric.value, style: .continuous)
                            .fill(LKColor.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: metric.value, style: .continuous)
                                    .strokeBorder(LKColor.separator, lineWidth: 1)
                            }
                            .frame(width: 64, height: 64)
                        Text(verbatim: "\(metric.name) \(Int(metric.value))")
                            .font(LKFont.caption)
                            .foregroundStyle(LKColor.textSecondary)
                    }
                }
            }
        }
    }
}

private struct MetricLabel: View {
    let metric: LKMetricToken

    var body: some View {
        Text(verbatim: "\(metric.name) \(Int(metric.value))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(LKColor.textSecondary)
            .frame(width: 112, alignment: .leading)
    }
}

// MARK: - Components

private struct ComponentsPanel: View {
    var body: some View {
        TokenPanel("Components", detail: "Specimens: the buttons here do nothing") {
            VStack(spacing: LKSpacing.m) {
                Button("Primary") {}
                    .buttonStyle(.lkPrimary)
                Button("Secondary") {}
                    .buttonStyle(.lkSecondary)
            }
            LKSectionHeader("Section header", detail: "Detail")
            // Two rows of three, so the longest titles fit an iPhone SE.
            VStack(alignment: .leading, spacing: LKSpacing.s) {
                HStack(spacing: LKSpacing.s) {
                    ForEach(LKMemberTone.allCases.prefix(3)) { tone in
                        LKPill(tone)
                    }
                }
                HStack(spacing: LKSpacing.s) {
                    ForEach(LKMemberTone.allCases.dropFirst(3)) { tone in
                        LKPill(tone)
                    }
                }
                LKPill("50 min", systemImage: "timer")
            }
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                Text("A card")
                    .font(LKFont.headline)
                    .foregroundStyle(LKColor.textPrimary)
                Text("Surface, hairline edge, card radius.")
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
            }
            .lkCard()
        }
    }
}

// MARK: - Layout

private struct TokenPanel<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(_ title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LKFont.title)
                    .foregroundStyle(LKColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(LKFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
