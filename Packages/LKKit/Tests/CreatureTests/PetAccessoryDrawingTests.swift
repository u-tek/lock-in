import CoreGraphics
import Foundation
import Model
import SwiftUI
import Testing
@testable import Creature

// Squad Boost's accessories (docs/milestones/M7.md), drawn on the pet. The Lab's
// `lab.pets.accessories` snapshot shows how they look; these pin that every one draws on every
// species and stage, stays in the pet's square, leaves the pet itself alone, isn't worn by the
// egg, and is an outline in Always-On.

/// The Live Activity's pet row, around the detail threshold, the squad page's tiles and card.
private let accessorySizes: [CGFloat] = [18, 20, 27, 28, 48, 64, 120, 160]

private let paints: Set<PetPaint> = [
    .scarf, .scarfShade, .partyHat, .hatTrim, .crownPetal, .crownLeaf, .frames, .lens, .bow, .bowKnot, .starClip,
]

private func code(_ species: PetSpecies, _ stage: Int, _ accessory: PetAccessory?) -> PetCode {
    PetCode(species: species.rawValue, stage: stage, accessory: accessory?.rawValue)
}

private func accessoryLayers(_ geometry: PetGeometry, reduced: Bool) -> [PetLayer] {
    geometry.accessoryLayers(.underFace, reduced: reduced) + geometry.accessoryLayers(.overFace, reduced: reduced)
}

@Suite struct PetAccessoryDrawingTests {
    /// Every accessory on every species at every stage but the egg, in and out of Always-On, at
    /// every size: something to draw, in the accessories' own paints.
    @Test(arguments: accessorySizes)
    func everyAccessoryDraws(size: CGFloat) {
        for species in PetSpecies.allCases {
            for stage in 1...5 {
                for accessory in PetAccessory.allCases {
                    for reduced in [false, true] {
                        let geometry = PetGeometry(code: code(species, stage, accessory), mood: 2, size: size)
                        let name = "\(accessory) on \(species) \(stage) at \(size), Always-On \(reduced)"
                        #expect(geometry.accessory == accessory, "\(name)")
                        let layers = accessoryLayers(geometry, reduced: reduced)
                        #expect(!layers.isEmpty, "\(name)")
                        for layer in layers {
                            #expect(!layer.path.isEmpty, "\(name): \(layer.paint)")
                            #expect(paints.contains(layer.paint) || layer.paint == .flowerCentre, "\(name): \(layer.paint)")
                        }
                        // And they're part of the drawing.
                        let drawn = geometry.layers(reduced: reduced).map(\.paint)
                        #expect(layers.allSatisfy { drawn.contains($0.paint) }, "\(name)")
                    }
                }
            }
        }
    }

    /// Nothing leaves the pet's square, strokes included, the same 2% as the pet itself.
    @Test(arguments: accessorySizes)
    func accessoriesStayInsideTheFrame(size: CGFloat) {
        let tolerance = size * 0.02
        let frame = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -tolerance, dy: -tolerance)
        for species in PetSpecies.allCases {
            for stage in 1...5 {
                for accessory in PetAccessory.allCases {
                    for mood in PetMood.allCases {
                        for reduced in [false, true] {
                            let geometry = PetGeometry(code: code(species, stage, accessory), mood: mood.rawValue, size: size)
                            for layer in accessoryLayers(geometry, reduced: reduced) {
                                let reach = (layer.lineWidth ?? 0) / 2
                                let bounds = layer.path.cgPath.boundingBoxOfPath.insetBy(dx: -reach, dy: -reach)
                                #expect(frame.contains(bounds), "\(accessory) on \(species) \(stage) \(mood) at \(size): \(layer.paint) at \(bounds)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The accessory goes on top of the pet: everything else is drawn exactly as without it.
    @Test(arguments: [CGFloat(18), 64])
    func thePetUnderneathIsUnchanged(size: CGFloat) {
        for species in PetSpecies.allCases {
            for stage in 1...4 {
                let plain = PetGeometry(code: code(species, stage, nil), mood: 3, size: size).layers(reduced: false).map(\.path)
                for accessory in PetAccessory.allCases {
                    let dressed = PetGeometry(code: code(species, stage, accessory), mood: 3, size: size)
                    let extra = accessoryLayers(dressed, reduced: false)
                    let all = dressed.layers(reduced: false)
                    #expect(all.count == plain.count + extra.count, "\(accessory) on \(species) \(stage)")
                    let rest = all.filter { layer in !extra.contains { $0.path == layer.path && $0.paint == layer.paint } }.map(\.path)
                    #expect(rest == plain, "\(accessory) on \(species) \(stage)")
                }
            }
        }
    }

    /// The scarf goes under the face, so the mouth stays on top where it rides up; the rest over it.
    @Test func theScarfIsUnderTheFace() {
        let geometry = PetGeometry(code: code(.puff, 2, .scarf), mood: 3, size: 18)
        let paints = geometry.layers(reduced: false).map(\.paint)
        let scarf = paints.firstIndex(of: .scarf) ?? Int.max
        let face = paints.firstIndex(of: .face) ?? Int.min
        #expect(scarf < face)
        let hat = PetGeometry(code: code(.puff, 2, .partyHat), mood: 3, size: 18).layers(reduced: false).map(\.paint)
        #expect((hat.firstIndex(of: .partyHat) ?? Int.min) > (hat.lastIndex(of: .face) ?? Int.max))
    }

    /// The egg wears nothing, and an accessory this version doesn't know is drawn as none.
    @Test func theEggAndUnknownAccessoriesWearNothing() {
        for species in PetSpecies.allCases {
            for accessory in PetAccessory.allCases {
                let egg = PetGeometry(code: code(species, 0, accessory), mood: 2, size: 64)
                let plainEgg = PetGeometry(code: code(species, 0, nil), mood: 2, size: 64)
                #expect(egg.accessory == nil)
                #expect(egg.layers(reduced: false).map(\.path) == plainEgg.layers(reduced: false).map(\.path))
            }
            let unknown = PetGeometry(code: PetCode(species: species.rawValue, stage: 2, accessory: 42), mood: 2, size: 64)
            let plain = PetGeometry(code: code(species, 2, nil), mood: 2, size: 64)
            #expect(unknown.accessory == nil)
            #expect(unknown.layers(reduced: false).map(\.path) == plain.layers(reduced: false).map(\.path))
        }
    }

    /// Always-On: outlines only, nothing filled.
    @Test(arguments: [CGFloat(18), 64, 160])
    func alwaysOnAccessoriesAreOutlines(size: CGFloat) {
        for species in PetSpecies.allCases {
            for accessory in PetAccessory.allCases {
                let geometry = PetGeometry(code: code(species, 3, accessory), mood: 2, size: size)
                for layer in accessoryLayers(geometry, reduced: true) {
                    #expect(layer.lineWidth != nil, "\(accessory) on \(species) at \(size): \(layer.paint) is filled")
                    #expect(layer.paint != .lens)
                }
            }
        }
        let palette = PetPalette(species: .puff, reduced: true, geometry: PetGeometry(code: code(.puff, 3, .glasses), mood: 2, size: size))
        #expect(palette.opacity(for: .frames) == 1)
    }

    /// Below the detail threshold the small parts go: the hat's dots, the crown's leaves and
    /// petals, the lenses.
    @Test func smallSizesDropTheSmallParts() {
        for species in PetSpecies.allCases {
            for accessory in PetAccessory.allCases {
                let small = PetGeometry(code: code(species, 2, accessory), mood: 2, size: PetGeometry.detailFrom - 1)
                let drawn = Set(accessoryLayers(small, reduced: false).map(\.paint))
                #expect(drawn.isDisjoint(with: [.crownLeaf, .lens, .flowerCentre]), "\(accessory) on \(species): \(drawn)")
                if accessory == .partyHat {
                    // Only the pompom in yellow: one trim layer.
                    #expect(accessoryLayers(small, reduced: false).filter { $0.paint == .hatTrim }.count == 1)
                }
            }
        }
    }

    @Test(arguments: [CGFloat(0), -10, .nan, .infinity])
    func aBrokenSizeDrawsNoAccessory(size: CGFloat) {
        for accessory in PetAccessory.allCases {
            let geometry = PetGeometry(code: code(.sprout, 2, accessory), mood: 2, size: size)
            #expect(accessoryLayers(geometry, reduced: false).isEmpty)
        }
    }

    @Test func voiceOverSaysWhatItWears() {
        #expect(PetView.accessibilityLabel(code: PetCode("sprout.2.a2"), mood: 3) == "Squad pet, teen sprout, happy, wearing a party hat")
        #expect(PetView.accessibilityLabel(code: PetCode("puff.3.a4"), mood: 2) == "Squad pet, adult puff, content, wearing glasses")
        #expect(PetView.accessibilityLabel(code: PetCode("ember.1.a6"), mood: 1) == "Squad pet, baby ember, hungry, wearing a star clip")
        // The egg wears nothing; an unknown accessory isn't named.
        #expect(PetView.accessibilityLabel(code: PetCode("ember.0.a2"), mood: 3) == "Squad pet, egg, happy")
        #expect(PetView.accessibilityLabel(code: PetCode("pebble.2.a42"), mood: 2) == "Squad pet, teen pebble, content")
    }

    /// Drawn for real: each accessory changes the picture, at the squad page's size and the Live
    /// Activity's.
    @Test(arguments: [CGFloat(18), 64])
    @MainActor func everyAccessoryRenders(size: CGFloat) throws {
        for species in PetSpecies.allCases {
            let plain = try Self.pixels(PetView(code: code(species, 2, nil), mood: 2, size: size), size: size)
            for accessory in PetAccessory.allCases {
                let dressed = try Self.pixels(PetView(code: code(species, 2, accessory), mood: 2, size: size), size: size)
                #expect(dressed != plain, "\(accessory) on \(species) at \(size) draws nothing")
            }
        }
    }

    @MainActor
    private static func pixels(_ view: some View, size: CGFloat) throws -> [UInt8] {
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
        return pixels
    }
}
