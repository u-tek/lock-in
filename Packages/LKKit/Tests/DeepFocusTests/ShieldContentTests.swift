import Foundation
import Model
import Testing
import UIKit
@testable import DeepFocus

@Suite struct ShieldContentTests {
    @Test func lockedNamesTheAppAndTheSquad() {
        let content = ShieldContent.locked(appName: "Instagram", withSquad: true)
        #expect(content.title == "You're locked in")
        #expect(content.subtitle == "Instagram can wait. Your squad's still going.")
        #expect(content.primaryButton == "Back to focus")
        #expect(content.secondaryButton == "Open anyway")
    }

    @Test func aloneThereIsNoSquadToMention() {
        let content = ShieldContent.locked(appName: "YouTube", withSquad: false)
        #expect(content.subtitle == "YouTube can wait. Your session's still going.")
        #expect(content.title == "You're locked in")
        #expect(content.secondaryButton == "Open anyway")
    }

    @Test(arguments: [nil, "", "   ", "\n"] as [String?])
    func withoutANameItsThisApp(name: String?) {
        #expect(ShieldContent.locked(appName: name, withSquad: true).subtitle == "This app can wait. Your squad's still going.")
        #expect(ShieldContent.lifted(appName: name).subtitle == "This app isn't blocked right now.")
    }

    @Test func websitesUseTheirDomain() {
        #expect(ShieldContent.locked(appName: "reddit.com", withSquad: true).subtitle.hasPrefix("reddit.com can wait."))
    }

    @Test func namesAreTrimmedAndLongOnesCut() {
        #expect(ShieldContent.displayName("  Messages ") == "Messages")
        let long = String(repeating: "Procrastination ", count: 4)
        let shown = ShieldContent.displayName(long)
        #expect(shown.count == ShieldContent.maximumNameLength)
        #expect(shown.hasSuffix("…"))
        #expect(shown.hasPrefix("Procrastination"))
        let exact = String(repeating: "a", count: ShieldContent.maximumNameLength)
        #expect(ShieldContent.displayName(exact) == exact)
    }

    @Test func aLeftoverShieldOffersOneButtonToUnlock() {
        let content = ShieldContent.lifted(appName: "TikTok")
        #expect(content.title == "You're not locked in")
        #expect(content.subtitle == "TikTok isn't blocked right now.")
        #expect(content.primaryButton == "Unlock")
        #expect(content.secondaryButton == nil)
    }

    @Test func looksLikeTheSystemInLockinsIndigo() {
        #expect(ShieldStyle.backgroundBlurStyle == .systemThickMaterial)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let indigo = UIColor.systemIndigo.resolvedColor(with: traits)
            #expect(ShieldStyle.tint.resolvedColor(with: traits) == indigo)
            #expect(ShieldStyle.primaryButtonBackgroundColor.resolvedColor(with: traits) == indigo)
            #expect(ShieldStyle.secondaryButtonLabelColor.resolvedColor(with: traits) == indigo)
            #expect(ShieldStyle.titleColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
            #expect(ShieldStyle.subtitleColor.resolvedColor(with: traits) == UIColor.secondaryLabel.resolvedColor(with: traits))
        }
        #expect(ShieldStyle.primaryButtonLabelColor == .white)
    }
}

@Suite struct ShieldIconTests {
    private let avatar = AvatarCode("b3.c7.e2.h4")

    @Test func theAppLeavesTheLocklingInAppGroupDefaults() throws {
        let suite = "DeepFocusTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ShieldIcon.avatarDefaultsKey == "LKAvatarCode")
        #expect(ShieldIcon.storedAvatar(defaults: defaults) == .default)
        ShieldIcon.storeAvatar(avatar, defaults: defaults)
        #expect(defaults.string(forKey: "LKAvatarCode") == "b3.c7.e2.h4")
        #expect(ShieldIcon.storedAvatar(defaults: defaults) == avatar)
        #expect(ShieldIcon.storedAvatar(defaults: nil) == .default)
    }

    @Test @MainActor func drawsTheLocklingAtThreeTimesItsPointSize() throws {
        let png = try #require(ShieldIcon.renderPNG(avatar))
        let image = try #require(UIImage(data: png)?.cgImage)
        #expect(image.width == Int(ShieldIcon.pointSize * 3))
        #expect(image.height == Int(ShieldIcon.pointSize * 3))
    }

    @Test @MainActor func theIconIsPointSized() {
        let image = ShieldIcon.image(avatar: avatar)
        #expect(image.size == CGSize(width: ShieldIcon.pointSize, height: ShieldIcon.pointSize))
        #expect(image.scale == 3)
    }

    /// The shield configuration extension may be called off the main thread.
    @Test func drawsOffTheMainThreadToo() async {
        let other = AvatarCode("b1.c2.e1.h0")
        let size = await Task.detached { ShieldIcon.image(avatar: other).size }.value
        #expect(size == CGSize(width: ShieldIcon.pointSize, height: ShieldIcon.pointSize))
    }

    @Test func theFallbackIsAPadlock() {
        #expect(ShieldIcon.fallbackSymbolName == "lock.fill")
        #expect(UIImage(systemName: ShieldIcon.fallbackSymbolName) != nil)
        #expect(ShieldIcon.fallbackImage().size.width > 0)
    }
}
