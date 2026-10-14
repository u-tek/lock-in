import SwiftUI
import Testing
@testable import DesignSystem

/// The cheers' colours (`LKColor.cheer(_:)`, by `Cheer.k`): the app's cheer picker and the Live
/// Activity draw each of the eight in its own system colour.
@Suite struct CheerColourTests {
    @Test func eachKindHasItsOwnSystemColour() {
        let colours = (0...7).map { LKColor.cheer($0) }
        #expect(colours == [Color.orange, .red, .yellow, .pink, .cyan, .indigo, .purple, .mint])
        #expect(Set(colours).count == 8)
    }

    @Test(arguments: [8, 11, -1, Int.max, Int.min])
    func unknownKindsAreSparklesMint(kind: Int) {
        // Model's `CheerKind(kind:)` draws a kind it doesn't know as sparkles, kind 7.
        #expect(LKColor.cheer(kind) == LKColor.cheer(7))
    }
}
