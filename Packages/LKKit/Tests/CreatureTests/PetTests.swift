import CoreGraphics
import Foundation
import Model
import SwiftUI
import Testing
@testable import Creature

// The squad pet (docs/milestones/M5.md). The Lab's `lab.pets` snapshots show how it looks; these
// pin what a picture can't be trusted to keep: every species, stage and mood draws and stays in its
// square, stages grow, moods differ, unknown species fall back, and Always-On is a line drawing.

/// The sizes the pet is drawn at: the Live Activity's pet row, just under and at the detail
/// threshold, the Lab's grids, the app's squad card.
private let petSizes: [CGFloat] = [18, 20, 24, 27, 28, 40, 56, 64, 120, 160]

/// Egg, baby, teen, adult, and the first two prestige forms.
private let stages = Array(0...5)

private func code(_ species: PetSpecies, _ stage: Int) -> PetCode {
    PetCode(species: species.rawValue, stage: stage)
}

@Suite struct PetSpeciesTests {
    /// The species the Creature module draws are the ones the server picks from, in order.
    @Test func theSpeciesAreTheRules() {
        #expect(PetSpecies.allCases.map(\.rawValue) == PetRules.species)
    }

    @Test(arguments: ["fox", "dragonling", "", "PUFF-ish", "owl"])
    func anUnknownSpeciesIsAPuff(name: String) {
        #expect(PetSpecies(name: name) == .puff)
    }

    @Test func knownNamesReadAsThemselves() {
        for species in PetSpecies.allCases {
            #expect(PetSpecies(name: species.rawValue) == species)
            #expect(PetSpecies(name: species.rawValue.uppercased()) == species)
        }
    }

    @Test func titlesAreUniqueAndCapitalised() {
        let titles = PetSpecies.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        for (species, title) in zip(PetSpecies.allCases, titles) {
            #expect(title.lowercased() == species.rawValue)
        }
    }
}

@Suite struct PetGeometryTests {
    /// Every combination, in and out of Always-On, has a body and a face (an egg has no face).
    @Test(arguments: petSizes)
    func everyPetDraws(size: CGFloat) {
        for species in PetSpecies.allCases {
            for stage in stages {
                for mood in PetMood.allCases {
                    for reduced in [false, true] {
                        let geometry = PetGeometry(code: code(species, stage), mood: mood.rawValue, size: size)
                        let paints = geometry.layers(reduced: reduced).map(\.paint)
                        let name = "\(species) \(stage) \(mood) at \(size), Always-On \(reduced)"
                        #expect(paints.contains(reduced ? .bodyOutline : (stage == 0 ? .egg : .body)), "\(name)")
                        #expect(paints.contains(.face) == (stage != 0), "\(name)")
                    }
                }
            }
        }
    }

    /// Nothing leaves the square, strokes included, so the pet lines up in rows and never pushes
    /// a Live Activity wider. The prototype measured at most 1.7% over, from round caps.
    @Test(arguments: petSizes)
    func everythingStaysInsideTheFrame(size: CGFloat) {
        let tolerance = size * 0.02
        let frame = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -tolerance, dy: -tolerance)
        for species in PetSpecies.allCases {
            for stage in stages {
                for mood in PetMood.allCases {
                    for reduced in [false, true] {
                        let geometry = PetGeometry(code: code(species, stage), mood: mood.rawValue, size: size)
                        for layer in geometry.layers(reduced: reduced) {
                            let reach = (layer.lineWidth ?? 0) / 2
                            let bounds = layer.path.boundingRect.insetBy(dx: -reach, dy: -reach)
                            #expect(frame.contains(bounds), "\(species) \(stage) \(mood) at \(size): \(layer.paint) at \(bounds)")
                        }
                    }
                }
            }
        }
    }

    /// A species from a newer server draws exactly as a puff: never a blank, never a trap.
    @Test(arguments: ["fox", "dragonling", "owl"])
    func anUnknownSpeciesDrawsAsAPuff(name: String) {
        for stage in stages {
            for mood in PetMood.allCases {
                for size in [CGFloat(20), 64] {
                    let unknown = PetGeometry(code: PetCode(species: name, stage: stage), mood: mood.rawValue, size: size)
                    let puff = PetGeometry(code: code(.puff, stage), mood: mood.rawValue, size: size)
                    #expect(unknown.species == .puff)
                    #expect(
                        unknown.layers(reduced: false).map(\.path) == puff.layers(reduced: false).map(\.path),
                        "\(name) \(stage) \(mood) at \(size)"
                    )
                }
            }
        }
    }

    /// Baby, teen and adult grow, at every size: the body's frame gets wider and taller, and what
    /// grows on it (leaves, flame tips, crystals, puffs) gets no smaller.
    @Test(arguments: [CGFloat(20), 64, 160])
    func stagesGrow(size: CGFloat) {
        for species in PetSpecies.allCases {
            let frames = [1, 2, 3].map { PetGeometry(code: code(species, $0), mood: 2, size: size) }
            for (smaller, larger) in zip(frames, frames.dropFirst()) {
                #expect(larger.bodyWidth > smaller.bodyWidth, "\(species) at \(size)")
                #expect(larger.bodyHeight > smaller.bodyHeight, "\(species) at \(size)")
                #expect(larger.bodyMinY < smaller.bodyMinY, "\(species) at \(size): stands taller")
                let smallerArea = Self.inkedBounds(smaller)
                let largerArea = Self.inkedBounds(larger)
                #expect(largerArea.height > smallerArea.height, "\(species) at \(size)")
            }
        }
    }

    /// With room for detail, each stage has more to it than the last: puffs, leaves, flame tips,
    /// crystals.
    @Test func stagesGrowInDetail() {
        for species in PetSpecies.allCases {
            let drawings = [1, 2, 3].map { PetGeometry(code: code(species, $0), mood: 2, size: 160) }
            let parts = drawings.map { Self.partCount($0) }
            #expect(parts[0] <= parts[1] && parts[1] <= parts[2], "\(species): \(parts)")
            #expect(parts[0] < parts[2], "\(species): \(parts)")
        }
    }

    /// Prestige is the adult, a little smaller, in a halo with sparkles; more sparkles from the
    /// second prestige form.
    @Test(arguments: [CGFloat(20), 64])
    func prestigeIsTheAdultInAHalo(size: CGFloat) {
        for species in PetSpecies.allCases {
            let adult = PetGeometry(code: code(species, 3), mood: 3, size: size)
            let prestige = PetGeometry(code: code(species, 4), mood: 3, size: size)
            let adultPaints = adult.layers(reduced: false).map(\.paint)
            let prestigePaints = prestige.layers(reduced: false).map(\.paint)
            #expect(!adultPaints.contains(.halo) && !adultPaints.contains(.sparkle))
            #expect(prestigePaints.contains(.glow) && prestigePaints.contains(.halo) && prestigePaints.contains(.sparkle))
            #expect(prestige.bodyWidth < adult.bodyWidth)
            #expect(prestige.prestigeLevel == 1)
        }
        let first = PetGeometry(code: code(.ember, 4), mood: 2, size: 64)
        let second = PetGeometry(code: code(.ember, 5), mood: 2, size: 64)
        let later = PetGeometry(code: code(.ember, 40), mood: 2, size: 64)
        #expect(Self.sparkles(first) != Self.sparkles(second))
        #expect(Self.sparkles(second) == Self.sparkles(later))
        #expect(later.growth == .prestige)
    }

    /// Every mood reads differently from every other, for every species and stage, even at the
    /// pet row's size.
    @Test(arguments: [CGFloat(18), 64])
    func everyMoodLooksDifferent(size: CGFloat) {
        for species in PetSpecies.allCases {
            for stage in stages {
                let drawings = PetMood.allCases.map { mood in
                    PetGeometry(code: code(species, stage), mood: mood.rawValue, size: size).layers(reduced: false).map(\.path)
                }
                for (i, first) in drawings.enumerated() {
                    for (j, second) in drawings.enumerated() where j > i {
                        #expect(first != second, "\(species) \(stage) at \(size): \(PetMood.allCases[i]) and \(PetMood.allCases[j]) look the same")
                    }
                }
            }
        }
    }

    /// Sad cries, at every size: the tear is what tells it apart in the pet row. Hungry's tummy
    /// rumbles where there's room for it.
    @Test func moodsHaveTheirExtras() {
        for species in PetSpecies.allCases {
            for stage in stages {
                for size in [CGFloat(18), 64] {
                    let sad = PetGeometry(code: code(species, stage), mood: 0, size: size).layers(reduced: false).map(\.paint)
                    #expect(sad.contains(.tear), "\(species) \(stage) at \(size)")
                }
                let hungry = PetGeometry(code: code(species, stage), mood: 1, size: 64).layers(reduced: false).map(\.paint)
                #expect(hungry.contains(.muted), "\(species) \(stage)")
            }
        }
    }

    /// The egg shows its mood by leaning: a happy egg wobbles furthest.
    @Test func theEggLeansWithItsMood() {
        let tilts = PetMood.allCases.map { PetGeometry(code: code(.sprout, 0), mood: $0.rawValue, size: 64).eggTilt }
        #expect(Set(tilts).count == tilts.count)
        #expect(tilts[PetMood.happy.rawValue] == tilts.map(abs).max().map { -$0 })
        #expect(tilts[PetMood.hungry.rawValue] == 0)
    }

    /// The egg carries its species' colours: the same shape, painted differently.
    @Test func eggsDifferOnlyInColour() {
        let eggs = PetSpecies.allCases.map { PetGeometry(code: code($0, 0), mood: 2, size: 64) }
        let shapes = eggs.map { $0.layers(reduced: false).map(\.path) }
        #expect(Set(shapes.map { $0.description }).count == 1)
    }

    @Test(arguments: [-7, 4, 99, Int.min, Int.max])
    func moodsOutOfRangeAreHeld(mood: Int) {
        let held = mood < 0 ? PetMood.sad : PetMood.happy
        let drawn = PetGeometry(code: code(.pebble, 2), mood: mood, size: 64)
        let expected = PetGeometry(code: code(.pebble, 2), mood: held.rawValue, size: 64)
        #expect(drawn.mood == held)
        #expect(drawn.layers(reduced: false).map(\.path) == expected.layers(reduced: false).map(\.path))
    }

    /// Below 28 points cheeks, highlights, catchlights, veins, flecks, the flower and the rumble
    /// would be specks: they're left off, and the face's lines get heavier.
    @Test func smallSizesDropTheDetail() {
        let detailOnly: Set<PetPaint> = [.shine, .cheek, .catchlight, .tongue, .partDetail, .petal, .flowerCentre, .muted]
        for species in PetSpecies.allCases {
            for stage in 1...5 {
                for mood in PetMood.allCases {
                    let small = PetGeometry(code: code(species, stage), mood: mood.rawValue, size: PetGeometry.detailFrom - 1)
                    #expect(!small.isDetailed)
                    let paints = Set(small.layers(reduced: false).map(\.paint))
                    #expect(paints.isDisjoint(with: detailOnly), "\(species) \(stage) \(mood): \(paints.intersection(detailOnly))")
                    let large = PetGeometry(code: code(species, stage), mood: mood.rawValue, size: PetGeometry.detailFrom)
                    #expect(large.isDetailed)
                    #expect(small.featureLine > large.featureLine)
                }
            }
        }
    }

    /// Always-On: outlines and a light face; nothing filled in the pet's colours, nothing that
    /// glints or glows.
    @Test(arguments: [CGFloat(18), 64, 160])
    func alwaysOnIsALineDrawing(size: CGFloat) {
        let glowing: Set<PetPaint> = [.body, .egg, .part, .core, .speckle, .shine, .cheek, .catchlight, .tongue, .glow, .petal, .flowerCentre, .partDetail]
        for species in PetSpecies.allCases {
            for stage in stages {
                for mood in PetMood.allCases {
                    let paints = Set(PetGeometry(code: code(species, stage), mood: mood.rawValue, size: size).layers(reduced: true).map(\.paint))
                    #expect(paints.contains(.bodyOutline), "\(species) \(stage) \(mood) at \(size)")
                    #expect(paints.isDisjoint(with: glowing), "\(species) \(stage) \(mood) at \(size): \(paints.intersection(glowing))")
                }
            }
        }
        let palette = PetPalette(species: .ember, reduced: true, geometry: PetGeometry(code: code(.ember, 3), mood: 2, size: size))
        #expect(palette.opacity(for: .bodyOutline) == 1)
        #expect(palette.opacity(for: .face) == 1)
        #expect(palette.opacity(for: .tear) < 1)
    }

    @Test(arguments: [CGFloat(0), -10, .nan, .infinity])
    func aBrokenSizeDrawsNothingAndDoesntTrap(size: CGFloat) {
        for species in PetSpecies.allCases {
            for stage in stages {
                let geometry = PetGeometry(code: code(species, stage), mood: 3, size: size)
                #expect(geometry.size == 0)
                for layer in geometry.layers(reduced: false) {
                    #expect(layer.path.boundingRect.width == 0 || layer.path.boundingRect.isNull)
                }
            }
        }
    }

    // MARK: - Helpers

    /// The union of every layer's bounds but the halo's, in points.
    private static func inkedBounds(_ geometry: PetGeometry) -> CGRect {
        geometry.layers(reduced: false)
            .filter { $0.paint != .glow && $0.paint != .halo && $0.paint != .sparkle }
            .map(\.path.boundingRect)
            .reduce(CGRect.null) { $0.union($1) }
    }

    /// How many separate shapes grow on the pet: scallops aside, the subpaths of its parts and of
    /// its outline's corners, counted as elements.
    private static func partCount(_ geometry: PetGeometry) -> Int {
        var count = 0
        for layer in geometry.layers(reduced: false) where [.part, .petal, .body].contains(layer.paint) {
            layer.path.forEach { element in
                if case .move = element {
                    count += 1
                }
                if case .curve = element {
                    count += 1
                }
            }
        }
        return count
    }

    private static func sparkles(_ geometry: PetGeometry) -> Path? {
        geometry.layers(reduced: false).first { $0.paint == .sparkle }?.path
    }
}

@Suite struct PetViewTests {
    @Test(arguments: [
        ("sprout.2", 3, "Squad pet, teen sprout, happy"),
        ("puff.1", 2, "Squad pet, baby puff, content"),
        ("ember.3", 1, "Squad pet, adult ember, hungry"),
        ("pebble.4", 0, "Squad pet, prestige pebble, sad"),
        ("pebble.5", 3, "Squad pet, prestige 2 pebble, happy"),
        // The egg keeps its species to itself until it hatches.
        ("ember.0", 3, "Squad pet, egg, happy"),
        // A species this version doesn't know is named as what's drawn.
        ("dragonling.3", 2, "Squad pet, adult puff, content"),
        ("%%%", 2, "Squad pet, egg, content"),
        // Moods out of range are held.
        ("sprout.1", 9, "Squad pet, baby sprout, happy"),
        ("sprout.1", -1, "Squad pet, baby sprout, sad"),
    ] as [(String, Int, String)])
    func accessibilityLabels(code: String, mood: Int, label: String) {
        #expect(PetView.accessibilityLabel(code: PetCode(code), mood: mood) == label)
    }

    /// Drawn for real, in and out of Always-On: every species, stage and mood produces an image of
    /// the asked size with something in it, and Always-On lights fewer pixels.
    @Test(arguments: [CGFloat(18), 64])
    @MainActor func rendersEveryPet(size: CGFloat) throws {
        for species in PetSpecies.allCases {
            for stage in 0...4 {
                for mood in PetMood.allCases {
                    let normal = try Self.inked(PetView(code: code(species, stage), mood: mood.rawValue, size: size), size: size)
                    let alwaysOn = try Self.inked(
                        PetView(code: code(species, stage), mood: mood.rawValue, size: size).environment(\.isLuminanceReduced, true),
                        size: size
                    )
                    let name = "\(species) \(stage) \(mood) at \(size)"
                    #expect(normal > 0.08, "\(name)")
                    #expect(alwaysOn > 0.01, "\(name), Always-On")
                    #expect(alwaysOn < normal, "\(name): Always-On should be an outline")
                }
            }
        }
    }

    /// The share of pixels with any opacity, drawn at 2x. Checks the image is the square asked
    /// for.
    @MainActor
    private static func inked(_ view: some View, size: CGFloat) throws -> Double {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        try #require(width == Int(size * 2) && height == Int(size * 2), "\(width) × \(height) for \(size)")
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn, "Couldn't read the drawn pet")
        var inked = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 0 {
            inked += 1
        }
        return Double(inked) / Double(width * height)
    }
}
