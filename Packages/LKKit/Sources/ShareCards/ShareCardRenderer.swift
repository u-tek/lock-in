import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Renders share cards to images: 1080 pixels wide, 1920 tall for a story and 1080 for a square.
@MainActor
public enum ShareCardRenderer {
    /// The card as an image at scale 1, so its pixel size is `kind.size`. Opaque: a story has no
    /// use for transparency, and the PNG is smaller without it.
    public static func uiImage(_ card: ShareCard, kind: ShareCardKind) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(kind: kind, card: card))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(kind.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The same, for SwiftUI.
    public static func image(_ card: ShareCard, kind: ShareCardKind) -> Image? {
        uiImage(card, kind: kind).map { Image(uiImage: $0) }
    }

    /// The same, as a PNG.
    public static func pngData(_ card: ShareCard, kind: ShareCardKind) -> Data? {
        uiImage(card, kind: kind)?.pngData()
    }
}

/// Why a card couldn't be shared.
public enum ShareCardError: Error, Sendable {
    /// SwiftUI couldn't draw it.
    case renderFailed
}

/// A share card as something to share: `ShareLink(item:preview:)` hands it to the share sheet as
/// a PNG. It's drawn only when the share sheet asks for it, not every time the screen with the
/// button is.
public struct ShareCardImage: Transferable, Sendable {
    public let card: ShareCard
    public let kind: ShareCardKind

    public init(card: ShareCard, kind: ShareCardKind) {
        self.card = card
        self.kind = kind
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            try await image.png()
        }
        .suggestedFileName("Lockin.png")
    }

    /// The card as a PNG.
    @MainActor
    public func png() throws -> Data {
        guard let data = ShareCardRenderer.pngData(card, kind: kind) else {
            throw ShareCardError.renderFailed
        }
        return data
    }
}
