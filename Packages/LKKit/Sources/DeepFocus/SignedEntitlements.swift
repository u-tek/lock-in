import Foundation

/// The entitlements the running executable was signed with, read from its code signature.
///
/// Deep Focus needs `com.apple.developer.family-controls`, which Apple grants per App ID on
/// request (docs/apple-setup.md step 7). Until it does, the app ships without it
/// (docs/milestones/M8.md), so asking FamilyControls for anything would only fail. Reading the
/// signature lets the app say it's waiting on Apple instead.
///
/// A Mach-O's `LC_CODE_SIGNATURE` load command points at a superblob whose entitlements slot holds
/// the same XML property list as the target's .entitlements file. Apple re-signs App Store and
/// TestFlight builds but keeps the entitlements, and the signature sits outside the encrypted
/// part of the binary. Simulator builds keep entitlements in a section instead and read as none.
enum SignedEntitlements {
    static let familyControlsKey = "com.apple.developer.family-controls"

    /// Whether this process was signed with Family Controls. Read once.
    static let grantsFamilyControls: Bool = {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let entitlements = SignedEntitlements.entitlements(inExecutable: data)
        else { return false }
        return SignedEntitlements.includesFamilyControls(entitlements)
    }()

    static func includesFamilyControls(_ entitlements: [String: Any]) -> Bool {
        entitlements[familyControlsKey] as? Bool ?? false
    }

    /// The entitlements in a Mach-O executable (thin, or the first slice of a universal one), or
    /// nil when it has no signature or no entitlements in it.
    static func entitlements(inExecutable data: Data) -> [String: Any]? {
        let bytes = Bytes(data: data)
        guard let magic = bytes.uint32(at: 0, bigEndian: true) else { return nil }
        switch magic {
        case fatMagic:
            guard let count = bytes.uint32(at: 4, bigEndian: true), count > 0,
                  let offset = bytes.uint32(at: 16, bigEndian: true)
            else { return nil }
            return entitlements(in: bytes, sliceAt: Int(offset))
        case fatMagic64:
            guard let count = bytes.uint32(at: 4, bigEndian: true), count > 0,
                  let offset = bytes.uint64(at: 16, bigEndian: true).flatMap({ Int(exactly: $0) })
            else { return nil }
            return entitlements(in: bytes, sliceAt: offset)
        default:
            return entitlements(in: bytes, sliceAt: 0)
        }
    }

    // <mach-o/loader.h>, <mach-o/fat.h> and the code signing blob formats.
    static let machMagic: UInt32 = 0xFEED_FACE
    static let machMagic64: UInt32 = 0xFEED_FACF
    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    static let codeSignatureCommand: UInt32 = 0x1D
    static let superBlobMagic: UInt32 = 0xFADE_0CC0
    static let entitlementsMagic: UInt32 = 0xFADE_7171
    static let entitlementsSlot: UInt32 = 5

    /// One architecture's Mach-O, little-endian: find `LC_CODE_SIGNATURE`.
    private static func entitlements(in bytes: Bytes, sliceAt slice: Int) -> [String: Any]? {
        guard let magic = bytes.uint32(at: slice, bigEndian: false) else { return nil }
        let headerSize: Int
        switch magic {
        case machMagic64: headerSize = 32
        case machMagic: headerSize = 28
        default: return nil
        }
        guard let commandCount = bytes.uint32(at: slice + 16, bigEndian: false) else { return nil }
        var cursor = slice + headerSize
        for _ in 0..<min(Int(commandCount), 4_096) {
            guard let command = bytes.uint32(at: cursor, bigEndian: false),
                  let size = bytes.uint32(at: cursor + 4, bigEndian: false), size >= 8
            else { return nil }
            if command == codeSignatureCommand {
                guard let offset = bytes.uint32(at: cursor + 8, bigEndian: false) else { return nil }
                return entitlements(in: bytes, superBlobAt: slice + Int(offset))
            }
            cursor += Int(size)
        }
        return nil
    }

    /// The signature's superblob, big-endian: find the entitlements slot and parse its plist.
    private static func entitlements(in bytes: Bytes, superBlobAt start: Int) -> [String: Any]? {
        guard bytes.uint32(at: start, bigEndian: true) == superBlobMagic,
              let count = bytes.uint32(at: start + 8, bigEndian: true)
        else { return nil }
        for index in 0..<min(Int(count), 64) {
            let entry = start + 12 + index * 8
            guard let type = bytes.uint32(at: entry, bigEndian: true),
                  let offset = bytes.uint32(at: entry + 4, bigEndian: true)
            else { return nil }
            guard type == entitlementsSlot else { continue }
            let blob = start + Int(offset)
            guard bytes.uint32(at: blob, bigEndian: true) == entitlementsMagic,
                  let length = bytes.uint32(at: blob + 4, bigEndian: true),
                  let xml = bytes.slice(from: blob + 8, to: blob + Int(length))
            else { return nil }
            let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil)
            return plist as? [String: Any]
        }
        return nil
    }

    /// Bounds-checked reads from the executable's bytes.
    private struct Bytes {
        let data: Data

        func uint32(at offset: Int, bigEndian: Bool) -> UInt32? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let base = data.startIndex + offset
            var value: UInt32 = 0
            for index in 0..<4 {
                value = value << 8 | UInt32(data[base + (bigEndian ? index : 3 - index)])
            }
            return value
        }

        func uint64(at offset: Int, bigEndian: Bool) -> UInt64? {
            guard let first = uint32(at: offset, bigEndian: bigEndian),
                  let second = uint32(at: offset + 4, bigEndian: bigEndian)
            else { return nil }
            return bigEndian
                ? UInt64(first) << 32 | UInt64(second)
                : UInt64(second) << 32 | UInt64(first)
        }

        func slice(from start: Int, to end: Int) -> Data? {
            guard start >= 0, start <= end, end <= data.count else { return nil }
            return data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
        }
    }
}
