import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct PetMoodTests {
    @Test func moodsAreHeldToTheirRange() {
        #expect(LKPalette.petMoods.count == 4)
        #expect(LKPalette.petMood(-1) == LKPalette.petMood0)
        #expect(LKPalette.petMood(0) == LKPalette.petMood0)
        #expect(LKPalette.petMood(2) == LKPalette.petMood2)
        #expect(LKPalette.petMood(3) == LKPalette.petMood3)
        #expect(LKPalette.petMood(7) == LKPalette.petMood3)
    }

    @Test func moodsAreDistinguishable() {
        // A softer bar than the member states: the pet is one creature at a time, so moods are
        // rarely seen side by side.
        for scheme in appearances {
            for vision in LKColorVision.allCases {
                let minimum = vision == .typical ? 0.10 : 0.06
                for (a, b) in pairs(LKPalette.petMoods) {
                    let d = perceivedDistance(a.value(in: scheme), b.value(in: scheme), for: vision)
                    #expect(d >= minimum, "\(a.name) and \(b.name), \(scheme), \(vision.rawValue): \(d)")
                }
            }
        }
    }

    @Test func moodsAreVisible() {
        // Mood colours draw shapes (the pet, its ring), not text, so 3:1 is the bar.
        for scheme in appearances {
            for mood in LKPalette.petMoods {
                for background in [LKPalette.background, LKPalette.surface] {
                    let ratio = mood.contrastRatio(on: background, in: scheme)
                    #expect(ratio >= 3, "\(mood.name) on \(background.name), \(scheme): \(ratio)")
                }
            }
        }
        for mood in LKPalette.petMoods {
            for background in [LKPalette.liveActivityBackground, LKPalette.islandBackground] {
                let ratio = mood.contrastRatio(on: background, in: .dark)
                #expect(ratio >= 3, "\(mood.name) on \(background.name): \(ratio)")
            }
        }
    }

    @Test func moodsBrightenAsTheyImprove() {
        // Lightness alone orders the ramp, so it reads without hue.
        for scheme in appearances {
            let lightness = LKPalette.petMoods.map { OKLab($0.value(in: scheme)).l }
            #expect(lightness == lightness.sorted(), "\(scheme): \(lightness)")
        }
    }
}
