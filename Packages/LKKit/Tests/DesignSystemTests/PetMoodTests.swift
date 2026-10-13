import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

@Suite struct PetMoodTests {
    @Test func moodsAreHeldToTheirRange() {
        #expect(LKColorCatalogue.petMoods.count == 4)
        #expect(LKColorCatalogue.petMood(-1) == LKColorCatalogue.petMood0)
        #expect(LKColorCatalogue.petMood(0) == LKColorCatalogue.petMood0)
        #expect(LKColorCatalogue.petMood(1) == LKColorCatalogue.petMood1)
        #expect(LKColorCatalogue.petMood(2) == LKColorCatalogue.petMood2)
        #expect(LKColorCatalogue.petMood(3) == LKColorCatalogue.petMood3)
        #expect(LKColorCatalogue.petMood(7) == LKColorCatalogue.petMood3)
        #expect(LKColorCatalogue.petMood(.min) == LKColorCatalogue.petMood0)
        #expect(LKColorCatalogue.petMood(.max) == LKColorCatalogue.petMood3)

        // The colours views draw clamp the same way. Each is one stored `Color`, so equal here
        // means the very same one.
        #expect(LKColor.petMood(-1) == LKColor.petMood0)
        #expect(LKColor.petMood(1) == LKColor.petMood1)
        #expect(LKColor.petMood(2) == LKColor.petMood2)
        #expect(LKColor.petMood(7) == LKColor.petMood3)
    }

    @Test func moodsWearTheSystemColoursInTheSystemDoc() {
        // design/SYSTEM.md: grey, orange, mint, green, from lowest to happiest.
        let expected: [(String, UIColor)] = [
            ("systemGray", .systemGray), ("systemOrange", .systemOrange),
            ("systemMint", .systemMint), ("systemGreen", .systemGreen),
        ]
        for (mood, (name, system)) in zip(LKColorCatalogue.petMoods, expected) {
            #expect(mood.uiKitName == name, "\(mood.name)")
            for scheme in appearances {
                #expect(distance(mood.resolved(in: scheme), resolve(system, in: scheme)) < 0.001, "\(mood.name), \(scheme)")
            }
        }
    }

    @Test func moodsAreDistinct() {
        // The pet is one creature at a time, so moods are rarely side by side, but a mood
        // change still has to show. The closest system pair here is about 0.4 apart.
        for scheme in appearances {
            for (a, b) in pairs(LKColorCatalogue.petMoods) {
                let d = distance(a.resolved(in: scheme), b.resolved(in: scheme))
                #expect(d > 0.15, "\(a.name) and \(b.name), \(scheme): \(d)")
            }
        }
    }
}
