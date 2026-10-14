import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// QR codes for invite links, drawn by Core Image.
///
/// Core Image makes one pixel per module. Scaling that up smoothly would blur the edges a camera
/// reads, so it's scaled by a whole number on the CPU side and drawn without interpolation.
public enum FriendCodeQR {
    /// The QR code for `text`, about `pixels` wide (never smaller than the code itself), black on
    /// white. Show it on white with a margin: cameras need the quiet zone. Nil if Core Image fails.
    public static func uiImage(for text: String, pixels: CGFloat = 512) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // M: about 15% of the code can be damaged and still read. Enough for a screen, and it
        // keeps the modules large.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let modules = output.extent.width
        guard modules > 0 else { return nil }
        let scale = max(1, (pixels / modules).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The same as a SwiftUI image that stays crisp at any size: give it a square frame.
    @MainActor
    public static func image(for text: String, pixels: CGFloat = 512) -> Image? {
        uiImage(for: text, pixels: pixels).map { uiImage in
            Image(uiImage: uiImage)
                .interpolation(.none)
                .resizable()
        }
    }
}
