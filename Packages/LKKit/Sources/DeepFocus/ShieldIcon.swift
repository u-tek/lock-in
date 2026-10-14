import Core
import Creature
import Foundation
import Model
import SwiftUI
import UIKit

/// The person's Lockling for the shield's icon, drawn from the avatar code the app leaves in the
/// App Group.
///
/// The app must call `storeAvatar(_:)` at launch and whenever the Lockling changes: the shield
/// configuration extension can't see the app's session file, only App Group defaults
/// (`"LKAvatarCode"`). Without it the shield shows the default Lockling.
public enum ShieldIcon {
    /// App Group defaults key holding the Lockling's `AvatarCode.code`, e.g. "b3.c7.e2.h4".
    public static let avatarDefaultsKey = "LKAvatarCode"
    /// The icon's size in points. The Lockling stays inside it, hat included.
    public static let pointSize: CGFloat = 64
    static let scale: CGFloat = 3
    /// Drawn instead when the Lockling can't be.
    public static let fallbackSymbolName = "lock.fill"

    /// For the app: remembers the Lockling for the shield.
    public static func storeAvatar(_ avatar: AvatarCode, defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(avatar.code, forKey: avatarDefaultsKey)
    }

    /// The Lockling the app stored, or the default one.
    public static func storedAvatar(defaults: UserDefaults? = AppGroup.defaults()) -> AvatarCode {
        defaults?.string(forKey: avatarDefaultsKey).map { AvatarCode($0) } ?? .default
    }

    /// The icon for `ShieldConfiguration`: the Lockling (the stored one when `avatar` is nil),
    /// focusing, or a padlock symbol if it can't be drawn. Callable from any thread.
    ///
    /// ImageRenderer needs the main actor, so off the main thread this waits for the main queue.
    /// The shield must be answered quickly, so each Lockling is drawn once per process and kept.
    public static func image(avatar: AvatarCode? = nil) -> UIImage {
        let avatar = avatar ?? storedAvatar()
        let png: Data?
        if let cached = cache.png(for: avatar.code) {
            png = cached
        } else {
            png = renderOnMain(avatar)
            if let png {
                cache.store(png, for: avatar.code)
            }
        }
        guard let png, let image = UIImage(data: png, scale: scale) else {
            deepFocusLog.error("Couldn't draw the Lockling for the shield; using the symbol")
            return fallbackImage()
        }
        return image
    }

    /// The Lockling as a PNG, `pointSize` square at `scale`. Nil if ImageRenderer gives nothing.
    @MainActor
    static func renderPNG(
        _ avatar: AvatarCode,
        pointSize: CGFloat = ShieldIcon.pointSize,
        scale: CGFloat = ShieldIcon.scale
    ) -> Data? {
        let renderer = ImageRenderer(content: CreatureView(avatar: avatar, pose: .focusing, size: pointSize))
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }

    /// The padlock symbol in the tint.
    public static func fallbackImage() -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize * 0.6, weight: .semibold)
        guard let symbol = UIImage(systemName: fallbackSymbolName, withConfiguration: configuration) else {
            return UIImage()
        }
        return symbol.withTintColor(ShieldStyle.tint, renderingMode: .alwaysOriginal)
    }

    private static func renderOnMain(_ avatar: AvatarCode) -> Data? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { renderPNG(avatar) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { renderPNG(avatar) }
        }
    }

    private static let cache = PNGCache()
}

/// Drawn Locklings by avatar code. A shield extension draws one, maybe two, in its life.
private final class PNGCache: @unchecked Sendable {
    private let lock = NSLock()
    private var pngs: [String: Data] = [:]

    func png(for code: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return pngs[code]
    }

    func store(_ png: Data, for code: String) {
        lock.lock()
        defer { lock.unlock() }
        pngs[code] = png
    }
}
