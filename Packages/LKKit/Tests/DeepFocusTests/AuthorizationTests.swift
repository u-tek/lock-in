import FamilyControls
import Foundation
import Testing
@testable import DeepFocus

// Only the mapping and the not-entitled path: nothing here calls AuthorizationCenter.

@Suite struct AuthorizationStatusTests {
    @Test func withoutTheEntitlementItsWaitingOnApple() {
        for system in [AuthorizationStatus.notDetermined, .denied, .approved] {
            #expect(DeepFocusAuthorization.Status(isEntitled: false, system: system) == .notEntitled)
        }
    }

    @Test func withItFamilyControlsDecides() {
        #expect(DeepFocusAuthorization.Status(isEntitled: true, system: .notDetermined) == .notDetermined)
        #expect(DeepFocusAuthorization.Status(isEntitled: true, system: .denied) == .denied)
        #expect(DeepFocusAuthorization.Status(isEntitled: true, system: .approved) == .approved)
    }

    @Test func cancellingIsntAFailure() {
        #expect(DeepFocusAuthorization.Failure(FamilyControlsError.authorizationCanceled) == nil)
    }

    @Test func failuresAreSortedForTheAlert() {
        typealias Failure = DeepFocusAuthorization.Failure
        #expect(Failure(FamilyControlsError.restricted) == .restricted)
        #expect(Failure(FamilyControlsError.authenticationMethodUnavailable) == .noPasscode)
        #expect(Failure(FamilyControlsError.networkError) == .network)
        #expect(Failure(FamilyControlsError.unavailable) == .unavailable)
        #expect(Failure(FamilyControlsError.invalidArgument) == .failed)
        #expect(Failure(CocoaError(.featureUnsupported)) == .failed)
        #expect(Failure(Failure.network) == .network)
    }

    @Test func everyFailureHasWords() {
        let all: [DeepFocusAuthorization.Failure] = [.restricted, .noPasscode, .network, .unavailable, .failed]
        for failure in all {
            let text = failure.errorDescription ?? ""
            #expect(!text.isEmpty)
            #expect(text.hasSuffix("."))
        }
    }
}

@Suite @MainActor struct AuthorizationTests {
    @Test func notEntitledNeverAsks() async throws {
        let authorization = DeepFocusAuthorization(isEntitled: false)
        #expect(authorization.status == .notEntitled)
        #expect(!authorization.isEntitled)
        try await authorization.request()
        authorization.refresh()
        #expect(authorization.status == .notEntitled)
    }

    @Test func previewsShowWhatTheyreGiven() async throws {
        let approved = DeepFocusAuthorization.preview(.approved)
        #expect(approved.status == .approved)
        #expect(approved.isEntitled)
        try await approved.request()
        #expect(approved.status == .approved)
        #expect(!DeepFocusAuthorization.preview(.notEntitled).isEntitled)
    }
}

@Suite struct SignedEntitlementsTests {
    private static func be32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private static func plist(_ entitlements: [String: Any]) throws -> [UInt8] {
        Array(try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0))
    }

    /// A code signature: a code directory stub, then the entitlements blob.
    private static func superBlob(entitlements xml: [UInt8]) -> [UInt8] {
        let codeDirectory = be32(0xFADE_0C02) + be32(8)
        let entitlements = be32(0xFADE_7171) + be32(UInt32(8 + xml.count)) + xml
        let header = 12 + 2 * 8
        var blob = be32(0xFADE_0CC0)
        blob += be32(UInt32(header + codeDirectory.count + entitlements.count))
        blob += be32(2)
        blob += be32(0) + be32(UInt32(header))
        blob += be32(5) + be32(UInt32(header + codeDirectory.count))
        return blob + codeDirectory + entitlements
    }

    /// A 64-bit Mach-O with an LC_UUID, and an LC_CODE_SIGNATURE when there's a signature.
    private static func machO(signature: [UInt8]?) -> [UInt8] {
        let uuidCommand = le32(0x1B) + le32(24) + [UInt8](repeating: 0xAB, count: 16)
        let signatureCommandSize = 16
        let commandsSize = uuidCommand.count + (signature == nil ? 0 : signatureCommandSize)
        var bytes = le32(0xFEED_FACF) + le32(0x0100_000C) + le32(0) + le32(2)
        bytes += le32(signature == nil ? 1 : 2) + le32(UInt32(commandsSize)) + le32(0) + le32(0)
        bytes += uuidCommand
        if let signature {
            let offset = 32 + commandsSize + 8
            bytes += le32(0x1D) + le32(UInt32(signatureCommandSize))
            bytes += le32(UInt32(offset)) + le32(UInt32(signature.count))
            bytes += [UInt8](repeating: 0, count: 8)
            bytes += signature
        }
        return bytes
    }

    private static func signed(_ entitlements: [String: Any]) throws -> Data {
        Data(machO(signature: superBlob(entitlements: try plist(entitlements))))
    }

    @Test func readsTheEntitlementsFromTheSignature() throws {
        let data = try Self.signed([
            "com.apple.developer.family-controls": true,
            "com.apple.security.application-groups": ["group.com.example.lockin"],
        ])
        let entitlements = try #require(SignedEntitlements.entitlements(inExecutable: data))
        #expect(entitlements["com.apple.security.application-groups"] as? [String] == ["group.com.example.lockin"])
        #expect(SignedEntitlements.includesFamilyControls(entitlements))
    }

    @Test func familyControlsMustBeThereAndTrue() throws {
        let without = try #require(SignedEntitlements.entitlements(inExecutable: try Self.signed(["aps-environment": "production"])))
        #expect(!SignedEntitlements.includesFamilyControls(without))
        let off = try #require(SignedEntitlements.entitlements(inExecutable: try Self.signed([SignedEntitlements.familyControlsKey: false])))
        #expect(!SignedEntitlements.includesFamilyControls(off))
    }

    @Test func aUniversalBinaryIsReadFromItsFirstSlice() throws {
        let slice = Array(try Self.signed([SignedEntitlements.familyControlsKey: true]))
        let sliceOffset = 64
        var fat = Self.be32(0xCAFE_BABE) + Self.be32(1)
        fat += Self.be32(0x0100_000C) + Self.be32(0)
        fat += Self.be32(UInt32(sliceOffset)) + Self.be32(UInt32(slice.count)) + Self.be32(6)
        fat += [UInt8](repeating: 0, count: sliceOffset - fat.count)
        fat += slice
        let entitlements = try #require(SignedEntitlements.entitlements(inExecutable: Data(fat)))
        #expect(SignedEntitlements.includesFamilyControls(entitlements))
    }

    @Test func unsignedOrNotAnExecutableReadsAsNone() throws {
        #expect(SignedEntitlements.entitlements(inExecutable: Data(Self.machO(signature: nil))) == nil)
        #expect(SignedEntitlements.entitlements(inExecutable: Data()) == nil)
        #expect(SignedEntitlements.entitlements(inExecutable: Data("#!/bin/sh\necho hi\n".utf8)) == nil)
    }

    @Test func aTruncatedSignatureReadsAsNone() throws {
        let data = try Self.signed([SignedEntitlements.familyControlsKey: true])
        #expect(SignedEntitlements.entitlements(inExecutable: data.prefix(data.count - 20)) == nil)
    }

    @Test func theKeyIsFamilyControls() {
        #expect(SignedEntitlements.familyControlsKey == "com.apple.developer.family-controls")
    }
}
