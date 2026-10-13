import SwiftUI

/// A small capsule label: a member's state, a preset ("50 min"), a count ("3 locked in").
///
/// The tint colours the fill and the symbol; the text stays ink. Coloured text on its own tint
/// drops under 4.5:1 for some tokens in light mode, and ink on a faint tint never does.
public struct LKPill: View {
    private let title: String
    private let systemImage: String?
    private let tint: Color

    /// - Parameter tint: The fill and symbol colour. The default is the accent's text variant,
    ///   which stays visible as a symbol on light backgrounds where the fill amber wouldn't.
    public init(_ title: String, systemImage: String? = nil, tint: Color = LKColor.accentText) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    /// A member's state: its symbol and word, in its colour.
    public init(_ tone: LKMemberTone) {
        self.init(tone.title, systemImage: tone.symbolName, tint: tone.color)
    }

    public var body: some View {
        HStack(spacing: LKSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(LKColor.textPrimary)
                .lineLimit(1)
        }
        .font(LKFont.caption.weight(.semibold))
        .padding(.horizontal, LKSpacing.s + LKSpacing.xxs)
        .padding(.vertical, LKSpacing.xs)
        .frame(minHeight: 24)
        .background(tint.opacity(LKColor.tintedFillOpacity), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
