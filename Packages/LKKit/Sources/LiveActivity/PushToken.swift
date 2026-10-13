import Foundation

/// Push tokens in the form APNs and the server take them: lowercase hex, two digits per byte.
///
/// ActivityKit hands tokens over as raw `Data`. `Data.description` and `String(describing:)`
/// print "32 bytes", not the bytes, so every token goes through here before it's uploaded or
/// shown on the APNs spike screen.
public enum PushToken {
    private static let digits = Array("0123456789abcdef".utf8)

    public static func hex(_ data: Data) -> String {
        var utf8: [UInt8] = []
        utf8.reserveCapacity(data.count * 2)
        for byte in data {
            utf8.append(digits[Int(byte >> 4)])
            utf8.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: utf8, as: UTF8.self)
    }
}
