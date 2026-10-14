import CoreGraphics
import Foundation
import Model
import SwiftUI
import Testing
@testable import Creature

// The Lockling (docs/milestones/M1.md). The previews show how it looks; these pin what a picture
// can't be trusted to keep: every state has its own pose, the catalogue is a stable wire format,
// unknown parts never trap, and the drawing stays inside its frame at every size.

/// The sizes the presentations draw: the compact island, the expanded island's chips, just under
/// and at the detail threshold, the Lock Screen row, the expanded island, the in-app hero.
private let sizes: [CGFloat] = [20, 22, 24, 27, 28, 34, 44, 52, 120]

@Suite struct PoseTests {
    @Test(arguments: [
        (MemberState.focusing, CreaturePose.focusing),
        (MemberState.onBreak, CreaturePose.onBreak),
        (MemberState.paused, CreaturePose.paused),
        (MemberState.done, CreaturePose.done),
        (MemberState.left, CreaturePose.left),
        (MemberState.slipped, CreaturePose.slipped),
    ])
    func everyMemberStateHasItsPose(state: MemberState, pose: CreaturePose) {
        #expect(CreaturePose(state) == pose)
    }

    @Test func noTwoStatesShareAPose() {
        let poses = MemberState.allCases.map(CreaturePose.init)
        #expect(Set(poses).count == MemberState.allCases.count)
        #expect(!poses.contains(.idle))
        #expect(!poses.contains(.celebrating))
    }

    /// The shackle is the Lockling's hair: closed while locked in, open when it isn't.
    @Test func theShackleIsClosedOnlyWhileLockedIn() {
        for pose in CreaturePose.allCases {
            switch pose {
            case .idle, .focusing, .paused:
                #expect(pose.shackleOpening == 0, "\(pose)")
            case .onBreak, .done, .left, .celebrating:
                #expect(pose.shackleOpening == 1, "\(pose)")
            case .slipped:
                #expect(pose.shackleOpening > 0 && pose.shackleOpening < 1)
            }
        }
    }
}

@Suite struct CatalogueTests {
    private static let parts: [(name: String, options: [CreatureOption])] = [
        ("bodies", CreatureCatalogue.bodies),
        ("colours", CreatureCatalogue.colours),
        ("eyes", CreatureCatalogue.eyes),
        ("hats", CreatureCatalogue.hats),
    ]

    /// Ids are the numbers in avatar codes that other members' phones read, so they run from 0
    /// with no gaps, in order.
    @Test func idsAreUniqueAndContiguousFromZero() {
        for part in Self.parts {
            #expect(part.options.map(\.id) == Array(0..<part.options.count), "\(part.name)")
        }
    }

    @Test func theDefaultIsFirstAndFree() {
        for part in Self.parts {
            let first = part.options.first
            #expect(first?.id == 0, "\(part.name)")
            #expect(first?.isPlus == false, "\(part.name)")
        }
    }

    /// Plus sells cosmetics (SPEC.md §2), but most of every part stays free.
    @Test func everyPartHasPlusOptionsButIsMostlyFree() {
        for part in Self.parts {
            let plus = part.options.filter(\.isPlus).count
            #expect(plus >= 1, "\(part.name)")
            #expect(plus * 2 < part.options.count, "\(part.name)")
        }
    }

    @Test func namesAreUniqueAndNotBlank() {
        for part in Self.parts {
            let names = part.options.map(\.name)
            #expect(Set(names).count == names.count, "\(part.name)")
            #expect(names.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(part.name)")
        }
    }

    @Test func thereIsEnoughToChooseFrom() {
        #expect(CreatureCatalogue.bodies.count >= 4)
        #expect(CreatureCatalogue.colours.count == 8)
        #expect(CreatureCatalogue.eyes.count >= 5)
        #expect(CreatureCatalogue.hats.count >= 6)
        #expect(CreatureCatalogue.hats.first?.name == "None")
    }

    @Test func coloursAreDistinctSystemColoursWithIndigoFirst() {
        let colours = CreatureCatalogue.colours.map { CreatureCatalogue.colour($0.id) }
        #expect(Set(colours).count == colours.count)
        #expect(CreatureCatalogue.colour(0) == .indigo)
    }

    @Test(arguments: [-1, 8, 99, Int.max])
    func anUnknownColourIsTheDefault(id: Int) {
        #expect(CreatureCatalogue.colour(id) == CreatureCatalogue.colour(0))
    }
}

@Suite struct GeometryTests {
    /// A code from a newer app version: every part out of range. It draws as the default, never
    /// traps.
    @Test(arguments: CreaturePose.allCases)
    func unknownPartsDrawAsTheDefaults(pose: CreaturePose) {
        let unknown = AvatarCode("b99.c99.e99.h99")
        for size in sizes {
            let drawn = LocklingGeometry(avatar: unknown, pose: pose, size: size)
            let expected = LocklingGeometry(avatar: .default, pose: pose, size: size)
            #expect(drawn.body == .classic)
            #expect(drawn.eyes == .dots)
            #expect(drawn.hat == .noHat)
            #expect(drawn.layers(reduced: false).map(\.path) == expected.layers(reduced: false).map(\.path), "\(pose) at \(size)")
        }
    }

    /// Every pose reads differently from every other, even at 20 points.
    @Test(arguments: sizes)
    func everyPoseLooksDifferent(size: CGFloat) {
        for avatar in [AvatarCode.default, AvatarCode("b3.c7.e2.h4"), AvatarCode("b4.c1.e4.h5")] {
            let drawings = CreaturePose.allCases.map { pose in
                LocklingGeometry(avatar: avatar, pose: pose, size: size).layers(reduced: false).map(\.path)
            }
            for (i, first) in drawings.enumerated() {
                for (j, second) in drawings.enumerated() where j > i {
                    let poses = "\(CreaturePose.allCases[i]) and \(CreaturePose.allCases[j])"
                    #expect(first != second, "\(avatar) at \(size): \(poses) look the same")
                }
            }
        }
    }

    /// Nothing leaves the square, in any pose, part or size, strokes included: rows line up and
    /// the island never grows. The prototype measured at most about 1% over, from round caps.
    @Test(arguments: sizes)
    func everythingStaysInsideTheFrame(size: CGFloat) {
        let tolerance = size * 0.02
        let frame = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -tolerance, dy: -tolerance)
        for body in CreatureCatalogue.bodies {
            for hat in CreatureCatalogue.hats {
                for eyes in CreatureCatalogue.eyes {
                    let avatar = AvatarCode(body: body.id, colour: 0, eyes: eyes.id, hat: hat.id)
                    for pose in CreaturePose.allCases {
                        for reduced in [false, true] {
                            let geometry = LocklingGeometry(avatar: avatar, pose: pose, size: size)
                            for layer in geometry.layers(reduced: reduced) {
                                let reach = (layer.lineWidth ?? 0) / 2
                                let bounds = layer.path.boundingRect.insetBy(dx: -reach, dy: -reach)
                                #expect(frame.contains(bounds), "\(avatar) \(pose) at \(size): \(layer.paint) at \(bounds)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Open: the short leg swings clear of the body. Closed: it's tucked inside.
    @Test(arguments: sizes)
    func theShortLegShowsOnlyWhenOpen(size: CGFloat) {
        for body in CreatureCatalogue.bodies {
            for pose in CreaturePose.allCases {
                let geometry = LocklingGeometry(avatar: AvatarCode(body: body.id), pose: pose, size: size)
                let tip = geometry.pt(geometry.shortLegTip.x, geometry.shortLegTip.y)
                    .applying(geometry.shackleTransform)
                let bodyTop = geometry.len(geometry.bodyMinY)
                if pose.shackleOpening == 0 {
                    #expect(tip.y > bodyTop, "\(body.name) \(pose) at \(size)")
                } else if pose.shackleOpening == 1 {
                    // Clear by most of a shackle's width, round cap and all, so it reads as open at
                    // a glance. The prototype measured 0.98 widths at island sizes, 2 above.
                    #expect(tip.y < bodyTop - geometry.len(geometry.shackleWidth) * 0.9, "\(body.name) \(pose) at \(size)")
                }
            }
        }
    }

    /// Below 28 points hats, props, cheeks and highlights would be specks: they're left off, and
    /// the face's lines get heavier.
    @Test func smallSizesDropTheDetail() {
        let detailOnly: Set<LocklingPaint> = [
            .shine, .cheek, .catchlight, .tongue, .limb, .sparkle, .confettiPink, .confettiTeal, .paper, .book,
            .bookSpine, .mugBand, .beanie, .beanieBand, .pompom, .headphones, .headphonePads, .cap, .capBrim,
            .petal, .gold,
        ]
        for hat in CreatureCatalogue.hats {
            let avatar = AvatarCode(body: 0, colour: 0, eyes: 3, hat: hat.id)
            for pose in CreaturePose.allCases {
                let small = LocklingGeometry(avatar: avatar, pose: pose, size: LocklingGeometry.detailFrom - 1)
                #expect(!small.isDetailed)
                #expect(small.hat == .noHat)
                let paints = Set(small.layers(reduced: false).map(\.paint))
                #expect(paints.isDisjoint(with: detailOnly), "\(hat.name) \(pose): \(paints.intersection(detailOnly))")

                let large = LocklingGeometry(avatar: avatar, pose: pose, size: LocklingGeometry.detailFrom)
                #expect(large.isDetailed)
                #expect(large.hat.rawValue == hat.id)
                #expect(small.featureLine > large.featureLine)
            }
        }
    }

    @Test func eachPoseHoldsItsProp() {
        let expected: [CreaturePose: LocklingPaint] = [
            .focusing: .book, .onBreak: .mugBand, .paused: .muted, .done: .sparkle, .slipped: .drop,
            .celebrating: .confettiTeal, .left: .limb,
        ]
        for (pose, paint) in expected {
            let paints = LocklingGeometry(avatar: .default, pose: pose, size: 120).layers(reduced: false).map(\.paint)
            #expect(paints.contains(paint), "\(pose)")
        }
        // Slipped keeps its sweat drop at island size: it's what tells it apart there.
        let small = LocklingGeometry(avatar: .default, pose: .slipped, size: 20).layers(reduced: false).map(\.paint)
        #expect(small.contains(.drop))
    }

    /// Always-On: an outline and a light face; nothing filled in the body's colour, nothing that
    /// glints.
    @Test(arguments: sizes)
    func alwaysOnIsALineDrawing(size: CGFloat) {
        for pose in CreaturePose.allCases {
            let geometry = LocklingGeometry(avatar: AvatarCode("b2.c5.e3.h1"), pose: pose, size: size)
            let paints = geometry.layers(reduced: true).map(\.paint)
            #expect(paints.contains(.bodyOutline), "\(pose)")
            for glowing in [LocklingPaint.body, .shine, .cheek, .catchlight, .tongue] {
                #expect(!paints.contains(glowing), "\(pose) at \(size): \(glowing)")
            }
        }
    }

    @Test func aMemberWhoLeftIsGreyAndFaded() {
        let geometry = LocklingGeometry(avatar: AvatarCode(colour: 3), pose: .left, size: 40)
        let left = LocklingPalette(colour: 3, pose: .left, reduced: false, geometry: geometry)
        #expect(left.bodyColour == .gray)
        #expect(left.overallOpacity < 1)
        let focusing = LocklingPalette(colour: 3, pose: .focusing, reduced: false, geometry: geometry)
        #expect(focusing.bodyColour == CreatureCatalogue.colour(3))
        #expect(focusing.overallOpacity == 1)
    }

    @Test(arguments: [CGFloat(0), -10, .nan, .infinity])
    func aBrokenSizeDrawsNothingAndDoesntTrap(size: CGFloat) {
        let geometry = LocklingGeometry(avatar: .default, pose: .celebrating, size: size)
        #expect(geometry.size == 0)
        for layer in geometry.layers(reduced: false) {
            #expect(layer.path.boundingRect.width == 0 || layer.path.boundingRect.isNull)
        }
    }
}

@Suite struct CreatureRenderingTests {
    /// Drawn for real, in and out of Always-On: every pose produces an image of the asked size
    /// with something in it.
    @Test(arguments: [CGFloat(20), 40, 120])
    @MainActor func rendersInEveryPose(size: CGFloat) throws {
        for pose in CreaturePose.allCases {
            for isLuminanceReduced in [false, true] {
                let view = CreatureView(avatar: AvatarCode("b3.c7.e2.h4"), pose: pose, size: size)
                    .environment(\.isLuminanceReduced, isLuminanceReduced)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage, "\(pose) at \(size)")
                #expect(image.width == Int(size * 2) && image.height == Int(size * 2), "\(pose) at \(size)")
                #expect(try Self.inkedFraction(of: image) > 0.05, "\(pose) at \(size), Always-On \(isLuminanceReduced)")
            }
        }
    }

    /// The share of pixels with any opacity.
    private static func inkedFraction(of image: CGImage) throws -> Double {
        let width = image.width
        let height = image.height
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
        try #require(drawn, "Couldn't read the drawn creature")
        var inked = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 0 {
            inked += 1
        }
        return Double(inked) / Double(width * height)
    }
}
