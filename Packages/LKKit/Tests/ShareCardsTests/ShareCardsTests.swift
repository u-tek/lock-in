import Foundation
import Model
import Testing
import UIKit
@testable import ShareCards

/// The share card (docs/milestones/M6.md): its words, who's on it, and the images it renders to.
@Suite struct ShareCardTests {
    static let you = AvatarCode(body: 0, colour: 2, eyes: 1, hat: 1)

    static func mates(_ count: Int) -> [ShareCard.Member] {
        (0..<count).map { index in
            ShareCard.Member(id: "u\(index)AAAAAAAA", name: "Mate \(index)", avatar: AvatarCode(body: index, colour: index))
        }
    }

    @Test func soloIsJustYou() {
        let card = ShareCard(avatar: Self.you, minutes: 25, streak: 3)
        #expect(!card.isSquad)
        #expect(card.lineup.map(\.id) == [ShareCard.youID])
        #expect(card.lineup.first?.name == "You")
        #expect(card.minutesLine == "minutes locked in")
        #expect(card.streakLine == "3-day streak")
        #expect(card.petLine == nil)
        #expect(card.printedCode == nil)
    }

    @Test func aSquadPutsYouFirstAndKeepsSixAtMost() {
        let card = ShareCard(avatar: Self.you, name: "Sam", squadName: "Library Goblins", squadmates: Self.mates(8), minutes: 50, streak: 0)
        #expect(card.isSquad)
        #expect(card.lineup.count == ShareCard.maxLocklings)
        #expect(card.lineup.first?.id == ShareCard.youID)
        #expect(card.lineup.first?.name == "Sam")
        #expect(card.lineup.dropFirst().map(\.id) == Self.mates(5).map(\.id))
        #expect(card.minutesLine == "minutes locked in together")
        #expect(card.streakLine == nil)
    }

    @Test func words() {
        var card = ShareCard(avatar: Self.you, minutes: 1, streak: 1)
        #expect(card.minutesNumber == "1")
        #expect(card.minutesLine == "minute locked in")
        #expect(card.streakLine == "1-day streak")
        card.minutes = -4
        #expect(card.minutesNumber == "0")
        card.pet = PetCode("sprout.2")
        #expect(card.petLine == "Teen sprout")
        card.pet = PetCode("ember.0")
        #expect(card.petLine == "Egg")
        card.pet = PetCode("pebble.4")
        #expect(card.petLine == "Prestige pebble")
    }

    @Test func theCodeIsPrintedPlainly() {
        var card = ShareCard(avatar: Self.you, minutes: 25, streak: 0, inviteCode: " kq7m-2xpa ")
        #expect(card.printedCode == "KQ7M2XPA")
        card.inviteCode = " - "
        #expect(card.printedCode == nil)
    }

    /// A long or empty name is cut down, or falls back to "You".
    @Test func yourNameIsKeptShort() {
        var card = ShareCard(avatar: Self.you, name: "   ", minutes: 25, streak: 0)
        #expect(card.lineup.first?.name == "You")
        card.name = "Alexandra-Catherine"
        #expect(card.lineup.first?.name.unicodeScalars.count ?? 0 <= LiveActivityLimits.maxNameLength)
    }

    @Test func kindsAreTheirSizes() {
        #expect(ShareCardKind.story.size == CGSize(width: 1_080, height: 1_920))
        #expect(ShareCardKind.square.size == CGSize(width: 1_080, height: 1_080))
    }
}

@MainActor
@Suite struct ShareCardRendererTests {
    static let solo = ShareCard(
        avatar: AvatarCode(body: 0, colour: 2, eyes: 1, hat: 1),
        minutes: 25,
        streak: 3,
        inviteCode: "KQ7M2XPA"
    )

    static let squad = ShareCard(
        avatar: AvatarCode(body: 0, colour: 2, eyes: 1, hat: 1),
        name: "Sam",
        squadName: "Library Goblins",
        squadmates: ShareCardTests.mates(3),
        minutes: 50,
        streak: 4,
        pet: PetCode("sprout.2"),
        petMood: 3,
        inviteCode: "KQ7M2XPA"
    )

    @Test(arguments: ShareCardKind.allCases)
    func rendersAt1080PixelsWide(kind: ShareCardKind) throws {
        for card in [Self.solo, Self.squad] {
            let image = try #require(ShareCardRenderer.uiImage(card, kind: kind))
            let pixels = try #require(image.cgImage)
            #expect(pixels.width == Int(kind.size.width))
            #expect(pixels.height == Int(kind.size.height))
        }
    }

    /// Every lineup size, from one to six, still renders.
    @Test func everySquadSizeRenders() throws {
        for count in 0...5 {
            var card = Self.squad
            card.squadmates = ShareCardTests.mates(count)
            for kind in ShareCardKind.allCases {
                let image = try #require(ShareCardRenderer.uiImage(card, kind: kind))
                #expect(image.cgImage?.width == 1_080)
            }
        }
    }

    /// Not a blank picture: the middle of a story (the Locklings) isn't the colour of its corner
    /// (the background).
    @Test func theCardHasSomethingOnIt() throws {
        let image = try #require(ShareCardRenderer.uiImage(Self.solo, kind: .story))
        let pixels = try #require(image.cgImage)
        let corner = try #require(Self.pixel(pixels, x: 4, y: 4))
        var differing = 0
        for y in stride(from: 300, to: 1_600, by: 50) {
            for x in stride(from: 100, to: 980, by: 40) {
                if let pixel = Self.pixel(pixels, x: x, y: y), pixel != corner {
                    differing += 1
                }
            }
        }
        #expect(differing > 50)
    }

    @Test func sharesAsAPNG() async throws {
        let data = try await ShareCardImage(card: Self.squad, kind: .story).png()
        let image = try #require(UIImage(data: data))
        #expect(image.size.width * image.scale == 1_080)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    /// One pixel's RGBA, read through a bitmap context of a known layout.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Moves the wanted pixel onto the context's one pixel. Core Graphics counts y up from
            // the bottom.
            context.draw(image, in: CGRect(
                x: -CGFloat(x),
                y: -CGFloat(image.height - 1 - y),
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            ))
            return true
        }
        return drawn ? bytes : nil
    }
}
