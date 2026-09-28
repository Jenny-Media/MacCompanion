import CryptoKit
import Foundation
import XCTest
@testable import CompanionSecurity

final class NativeVideoEnrollmentSigningV0Tests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw CocoaError(.fileNoSuchFile) }
            root = parent
        }
        let path = "crypto/native-video-enrollment-v0.1.json"
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
        XCTAssertEqual((manifest["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count, 1)
        return try JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/\(path)"))) as! [String: Any]
    }

    private func bytes(_ value: String) -> Data {
        let chars = Array(value.utf8)
        return Data(stride(from: 0, to: chars.count, by: 2).map {
            UInt8(String(decoding: chars[$0..<$0 + 2], as: UTF8.self), radix: 16)!
        })
    }

    private func input(_ fields: [String: Any]) throws -> Data {
        func id(_ key: String) -> UUID { UUID(uuidString: fields[key] as! String)! }
        func data(_ key: String) -> Data { bytes(fields[key] as! String) }
        func number(_ key: String) -> UInt64 { (fields[key] as! NSNumber).uint64Value }
        return try CompanionSecurityV0.nativeVideoEnrollmentSigningInput(
            hostID: id("hostID"), hostFingerprint: data("hostFingerprintHex"), clientID: id("clientID"),
            primaryConnectionID: data("primaryConnectionIDHex"), interactiveSessionID: id("interactiveSessionID"),
            authorizationEpoch: number("authorizationEpoch"), grantRevision: number("grantRevision"), policyRevision: number("policyRevision"),
            streamGeneration: id("streamGeneration"), surfaceID: id("surfaceID"), surfaceRevision: number("surfaceRevision"),
            coordinateSpaceRevision: number("coordinateSpaceRevision"), encodedWidth: UInt16(number("encodedWidth")),
            encodedHeight: UInt16(number("encodedHeight")), clientCertificateSHA256: data("clientCertificateSHA256Hex"),
            hostCertificateSHA256: data("hostCertificateSHA256Hex"), hostChallenge: data("hostChallengeHex"),
            issuedAtUnixMilliseconds: number("issuedAtUnixMilliseconds"), expiresAtUnixMilliseconds: number("expiresAtUnixMilliseconds"))
    }

    func testSigningBytesDigestAndSignatureMatchAuthoritativeVector() throws {
        let vector = try fixture(), fields = vector["inputs"] as! [String: Any], derived = vector["derived"] as! [String: String]
        let message = try input(fields)
        XCTAssertEqual(message, bytes(derived["signingInputHex"]!))
        XCTAssertEqual(Data(SHA256.hash(data: message)), bytes(derived["signingInputSHA256Hex"]!))
        XCTAssertTrue(try CompanionSecurityV0.verifySignature(rawSignature: bytes(derived["signatureRawHex"]!),
            signingInput: message, publicKeyX963: bytes(fields["sessionPublicKeyX963Hex"] as! String)))
    }

    func testEveryEnrollmentBindingFieldIsCoveredByTheSessionSignature() throws {
        let vector = try fixture(), fields = vector["inputs"] as! [String: Any], derived = vector["derived"] as! [String: String]
        for (key, value) in fields where key != "sessionPublicKeyX963Hex" {
            var changed = fields
            if let text = value as? String {
                if key.hasSuffix("Hex") {
                    var replacement = bytes(text)
                    replacement[0] ^= 1
                    changed[key] = replacement.map { String(format: "%02x", $0) }.joined()
                } else { changed[key] = UUID().uuidString }
            } else if let number = value as? NSNumber {
                // Move issuance later and expiry earlier to retain a valid
                // challenge window while checking both independently.
                changed[key] = key == "expiresAtUnixMilliseconds" ? number.uint64Value - 1 : number.uint64Value + 1
            } else { XCTFail("Unexpected fixture field \(key)"); continue }
            XCTAssertFalse(try CompanionSecurityV0.verifySignature(rawSignature: bytes(derived["signatureRawHex"]!),
                signingInput: input(changed), publicKeyX963: bytes(fields["sessionPublicKeyX963Hex"] as! String)), key)
        }
    }

    func testInvalidChallengeAndUnboundedExpiryAreRejectedBeforeSigning() throws {
        let fields = try fixture()["inputs"] as! [String: Any]
        for (key, value): (String, Any) in [
            ("hostChallengeHex", "00"), ("clientCertificateSHA256Hex", "00"),
            ("authorizationEpoch", 0), ("encodedWidth", 0),
            ("expiresAtUnixMilliseconds", 1724000015001),
            ("expiresAtUnixMilliseconds", 1724000000000),
        ] {
            var changed = fields; changed[key] = value
            XCTAssertThrowsError(try input(changed), key)
        }
    }
}
