import SwiftUI

extension View {
    /// A card: this view, padded, on a surface with a hairline edge, filling the width offered.
    public func lkCard(padding: CGFloat = LKSpacing.cardPadding, radius: CGFloat = LKRadius.card) -> some View {
        modifier(LKCardModifier(padding: padding, radius: radius))
    }

    /// The screen's background, under the safe areas too.
    public func lkScreenBackground() -> some View {
        background {
            LKColor.background.ignoresSafeArea()
        }
    }

    /// Glass behind this view, in `shape`: Liquid Glass on iOS 26 and later, a frosted material
    /// with a hairline edge before that. For floating controls over content (a bar over a
    /// scrolling list), not for cards, and not in the Live Activity, where the system draws its
    /// own background.
    public func lkGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LKGlassModifier(shape: shape, tint: tint))
    }

    /// Renders this view in the dark appearance, whatever the system's. The Live Activity (and
    /// the lab's previews of it) use this: on the Lock Screen and in StandBy it's a little night
    /// window in both appearances, on `LKColor.liveActivityBackground`, and every token resolves
    /// to the dark value that DesignSystemTests checks against that background.
    public func lkNightAppearance() -> some View {
        environment(\.colorScheme, .dark)
    }
}

struct LKCardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LKColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(LKColor.separator, lineWidth: 1)
            }
    }
}

struct LKGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(liquidGlass, in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.regularMaterial)
                        if let tint {
                            shape.fill(tint.opacity(LKColor.tintedFillOpacity))
                        }
                    }
                }
                .overlay {
                    shape.strokeBorder(LKColor.separator, lineWidth: 1)
                }
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlass: Glass {
        guard let tint else { return .regular }
        return .regular.tint(tint)
    }
}
