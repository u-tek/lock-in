import API
import Foundation
import Testing
import UIKit
@testable import Social

@Suite struct FriendCodeFormatTests {
    @Test func codesAreNormalisedAsTyped() {
        #expect(FriendCode.normalised("kq7m2xpa") == "KQ7M2XPA")
        #expect(FriendCode.normalised("KQ7M 2XPA") == "KQ7M2XPA")
        #expect(FriendCode.normalised(" kq7m-2xpa\n") == "KQ7M2XPA")
        #expect(FriendCode.normalised("KQ7M–2XPA") == "KQ7M2XPA")
        #expect(FriendCode.normalised("") == "")
    }

    @Test func onlyEightCharactersOfTheAlphabetAreWellFormed() {
        #expect(FriendCode.isWellFormed("KQ7M2XPA"))
        #expect(FriendCode.isWellFormed("ABCDEFGH"))
        #expect(!FriendCode.isWellFormed("KQ7M2XP"))
        #expect(!FriendCode.isWellFormed("KQ7M2XPAB"))
        // No 0/O or 1/I: they're too easy to misread.
        #expect(!FriendCode.isWellFormed("KQ7M2XP0"))
        #expect(!FriendCode.isWellFormed("KQ7M2XPO"))
        #expect(!FriendCode.isWellFormed("KQ7M2XP1"))
        #expect(!FriendCode.isWellFormed("KQ7M2XPI"))
        // Normalising comes first; lowercase isn't well formed by itself.
        #expect(!FriendCode.isWellFormed("kq7m2xpa"))
        #expect(FriendCode.alphabet.count == 32)
    }

    @Test func codesReadInTwoHalves() {
        #expect(FriendCode.spaced("KQ7M2XPA") == "KQ7M 2XPA")
        #expect(FriendCode.spaced("SHORT") == "SHORT")
    }
}

@Suite struct InviteLinkTests {
    @Test(arguments: [
        "lockin://j/KQ7M2XPA",
        "lockin://j/kq7m2xpa",
        "LOCKIN://J/KQ7M2XPA",
        "lockin://j/KQ7M2XPA/",
        "lockin://j/KQ7M-2XPA",
        "https://lockin.example/j/KQ7M2XPA",
        "https://api.lockin.workers.dev/j/kq7m2xpa",
        "https://lockin.example/J/KQ7M2XPA?ref=share",
    ])
    func linksCarryTheirCode(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(InviteLink(url: url)?.code == "KQ7M2XPA")
    }

    @Test(arguments: [
        "lockin://session/r7Kq2xP9aL",
        "lockin://j/",
        "lockin://j/KQ7M2XPA/extra",
        "lockin://j/NOTACODE0",
        "https://lockin.example/KQ7M2XPA",
        "https://lockin.example/x/j/KQ7M2XPA",
        "https://lockin.example/j/",
        "mailto:j@lockin.example",
        "ftp://lockin.example/j/KQ7M2XPA",
    ])
    func otherLinksAreNotInvites(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(InviteLink(url: url) == nil)
    }

    @Test func pastedTextFindsTheCode() {
        #expect(InviteLink(text: "KQ7M-2XPA")?.code == "KQ7M2XPA")
        #expect(InviteLink(text: "  kq7m 2xpa ")?.code == "KQ7M2XPA")
        #expect(InviteLink(text: "Lock in with me on Lockin https://lockin.example/j/KQ7M2XPA")?.code == "KQ7M2XPA")
        #expect(InviteLink(text: "hello there") == nil)
        #expect(InviteLink(text: "") == nil)
    }

    @Test func theAppLinkRoundTrips() throws {
        let link = try #require(InviteLink(code: "kq7m 2xpa"))
        #expect(link.appURL.absoluteString == "lockin://j/KQ7M2XPA")
        #expect(InviteLink(url: link.appURL) == link)
    }

    @Test func theShareLinkIsTheServers() {
        let code = FriendCode(code: "KQ7M2XPA", url: URL(string: "https://lockin.example/j/KQ7M2XPA")!, expiresAt: 0)
        #expect(InviteLink.shareURL(for: code) == code.url)
        #expect(InviteLink(url: InviteLink.shareURL(for: code))?.code == code.code)
    }
}

@Suite struct FriendCodeQRTests {
    @Test func theQRCodeIsSquareAndScaledByWholeModules() throws {
        let image = try #require(FriendCodeQR.uiImage(for: "https://lockin.example/j/KQ7M2XPA", pixels: 300))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == cgImage.height)
        #expect(cgImage.width <= 300)
        #expect(cgImage.width >= 150)
    }
}
