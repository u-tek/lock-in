import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The components lay out as documented. Their look is checked in the snapshots
/// (`lab.tokens.components`); these catch sizes drifting and the iOS 26 branches crashing, since
/// CI's simulator runs iOS 26 and takes the glass path.
@Suite struct ComponentTests {
    @Test @MainActor func iconTileIsSettingsSizedAtTheDefaultTextSize() {
        let size = fittingSize(of: tile.environment(\.dynamicTypeSize, .large))
        #expect(abs(size.width - LKIconTile.defaultSize) < 0.5, "\(size)")
        #expect(abs(size.height - LKIconTile.defaultSize) < 0.5, "\(size)")
    }

    @Test @MainActor func iconTileGrowsWithDynamicType() {
        let standard = fittingSize(of: tile.environment(\.dynamicTypeSize, .large))
        let larger = fittingSize(of: tile.environment(\.dynamicTypeSize, .accessibility2))
        #expect(larger.width > standard.width, "\(standard) → \(larger)")
        // Still square: the corner is a share of the side, so it keeps its shape as it grows.
        #expect(abs(larger.width - larger.height) < 0.5, "\(larger)")
    }

    @Test func iconTileCornerMatchesSettings() {
        // About 6.5 points on a 29-point tile, the app icon's proportion.
        let radius = LKIconTile.defaultSize * LKIconTile.cornerFraction
        #expect(radius > 6 && radius < 7, "\(radius)")
    }

    @Test @MainActor func buttonsLayOut() {
        let buttons = VStack {
            Button("Lock in") {}
                .lkProminentButton()
                .controlSize(.large)
            Button("Not now") {}
                .lkSecondaryButton()
        }
        let size = fittingSize(of: buttons)
        // Two system buttons stacked. Even a small one is 28 points tall, and the large one is
        // much more, so anything shorter means a style didn't draw.
        #expect(size.height >= 56, "\(size)")
        #expect(size.width > 0, "\(size)")
    }

    @Test @MainActor func cardsFillTheWidthOffered() {
        let width: CGFloat = 343
        for card in [AnyView(Text("Card").lkCard()), AnyView(Text("Card").lkMaterialCard())] {
            let size = UIHostingController(rootView: card)
                .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            #expect(size.width == width, "\(size)")
            #expect(size.height >= LKSpacing.cardPadding * 2, "\(size)")
        }
    }

    @MainActor
    private var tile: LKIconTile {
        LKIconTile(systemName: LKMemberTone.focusing.symbolName, color: LKColor.tint)
    }

    @MainActor
    private func fittingSize(of view: some View) -> CGSize {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    }
}
