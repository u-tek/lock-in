import SwiftUI

// Most content belongs in a `List` or `Form`, which draw their own grouped rows. These are for
// the few things that can't be a list row, such as the Home screen's Live Activity preview.
// Neither draws a border or a shadow: the system's cards don't (design/SYSTEM.md).

extension View {
    /// A card on the grouped background: this view, padded, filling the width offered, on
    /// `secondarySystemGroupedBackground` in a continuous 26-point rectangle. Put the screen on
    /// `LKColor.groupedBackground` so it reads like a list section beside real ones.
    public func lkCard(padding: CGFloat = LKSpacing.cardPadding) -> some View {
        modifier(LKCardModifier(padding: padding, fill: LKColor.secondaryGroupedBackground))
    }

    /// The same card on `.regularMaterial`, for something floating over other content (a bar over
    /// a scrolling list, a panel over an image), where the content behind should show through.
    /// Toolbars and the glass button styles already bring Liquid Glass; don't build it by hand.
    public func lkMaterialCard(padding: CGFloat = LKSpacing.cardPadding) -> some View {
        modifier(LKCardModifier(padding: padding, fill: Material.regular))
    }
}

struct LKCardModifier<Fill: ShapeStyle>: ViewModifier {
    let padding: CGFloat
    let fill: Fill

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
    }
}
