import Model
import SwiftUI
import Testing
import UIKit
@testable import LiveActivity

/// The squad pet's row on the Lock Screen and in StandBy: the pet drawn by `PetView`, its name
/// and its progress.
@Suite struct PetRowTests {
    /// Every pet the samples carry, plus an egg and a prestige form.
    private static let pets: [LiveActivityPresentation.Pet] = {
        let samples = LiveActivitySamples.catalogue(now: LiveActivitySamples.fixtureDate).compactMap(\.presentation.pet)
        let extra = ["ember.0", "pebble.4"].map { LiveActivityPresentation.Pet(.init(k: $0, md: 2, x: 0.5)) }
        return samples + extra
    }()

    @Test func theSquadSamplesHaveAPet() {
        #expect(Self.pets.count >= 4)
    }

    /// Drawn larger than its caption and let into the space round the row, so the row is no
    /// taller than its text and the layouts keep the heights LockScreenHeightTests measures.
    @Test func thePetDoesntMakeTheRowTaller() {
        #expect(ActivityMetrics.petRowCreature - 2 * ActivityMetrics.petRowOverhang <= 14)
        #expect(ActivityMetrics.petRowCreature >= 16)
        #expect(ActivityMetrics.petRowCreature < PetGeometrySizes.detailFrom)
    }

    @Test(arguments: [DynamicTypeSize.large, .xLarge])
    @MainActor func theRowIsAsTallAsItsText(textSize: DynamicTypeSize) {
        for pet in Self.pets {
            let row = Self.height(of: PetRow(pet: pet), textSize: textSize)
            let text = Self.height(of: Text(pet.title).font(ActivityFont.caption), textSize: textSize)
            #expect(row > 0, "\(pet.title)")
            #expect(row <= text + 0.5, "\(pet.title) at \(textSize): row \(row), text \(text)")
        }
    }

    /// The row draws, pet and all, in and out of Always-On. (CreatureTests check the pet itself
    /// at every species, stage and mood.)
    @Test @MainActor func everySamplePetsRowDraws() throws {
        for pet in Self.pets {
            for reduced in [false, true] {
                let row = PetRow(pet: pet)
                    .frame(width: 300)
                    .environment(\.isLuminanceReduced, reduced)
                let renderer = ImageRenderer(content: row)
                renderer.scale = 2
                let image = try #require(renderer.cgImage, "\(pet.title)")
                #expect(image.width == 600, "\(pet.title)")
                #expect(image.height > 0, "\(pet.title)")
            }
        }
    }

    @MainActor
    private static func height(of view: some View, textSize: DynamicTypeSize) -> CGFloat {
        let sized = view
            .dynamicTypeSize(textSize)
            .fixedSize(horizontal: false, vertical: true)
        return UIHostingController(rootView: sized)
            .sizeThatFits(in: CGSize(width: 343, height: CGFloat.greatestFiniteMagnitude))
            .height
    }
}

/// `PetGeometry` is internal to Creature; the size it starts drawing detail at is restated here,
/// so the pet row's size is checked against it.
private enum PetGeometrySizes {
    static let detailFrom: CGFloat = 28
}
