import Foundation
import XCTest
import CompanionWire
import CompanionInteractiveWire

final class InteractiveNativeVideoMessagesV0Tests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
        }
        let path = "valid/native-video-\(name).json"
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
        XCTAssertEqual((index["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count, 1)
        return try Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))
    }
    private func decode(_ name: String, _ data: Data) throws -> Data {
        func roundtrip<B: WireBody>(_ type: B.Type) throws -> Data { try WireCodec.encode(WireCodec.decode(WireEnvelope<B>.self, from: data)) }
        switch name {
        case "enroll-request": return try roundtrip(InteractiveNativeVideoEnrollmentRequestBodyV0.self)
        case "enroll-challenge": return try roundtrip(InteractiveNativeVideoEnrollmentChallengeBodyV0.self)
        case "enroll-proof": return try roundtrip(InteractiveNativeVideoEnrollmentProofBodyV0.self)
        case "present-request": return try roundtrip(InteractiveNativeVideoPresentationRequestBodyV0.self)
        case "present-receipt": return try roundtrip(InteractiveNativeVideoPresentationReceiptBodyV0.self)
        case "ready": return try roundtrip(InteractiveNativeVideoReadyBodyV0.self)
        case "cancel": return try roundtrip(InteractiveNativeVideoCancelBodyV0.self)
        default: return try roundtrip(InteractiveNativeVideoCancelledBodyV0.self)
        }
    }
    func testAllIndexedRecordsRoundtripAndRejectUnknownOrMissingKeys() throws {
        for name in ["enroll-request", "enroll-challenge", "enroll-proof", "ready", "cancel", "cancelled", "present-request", "present-receipt"] {
            let source = try fixture(name), encoded = try decode(name, source)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: source) as! NSDictionary, try JSONSerialization.jsonObject(with: encoded) as! NSDictionary)
            let record = try JSONSerialization.jsonObject(with: source) as! [String: Any]
            let body = record["body"] as! [String: Any]
            for removed in body.keys {
                var changed = record, fields = body; fields.removeValue(forKey: removed); changed["body"] = fields
                XCTAssertThrowsError(try decode(name, JSONSerialization.data(withJSONObject: changed)))
            }
            var changed = record, fields = body; fields["inputEnabled"] = true; changed["body"] = fields
            XCTAssertThrowsError(try decode(name, JSONSerialization.data(withJSONObject: changed)))
        }
    }
    func testCertificateNonceSignatureGeometryAndPortBoundsReject() throws {
        for (name, field, value) in [
            ("enroll-request", "clientCertificateDERBase64", "" as Any),
            ("enroll-request", "clientCertificateDERBase64", "AA" as Any),
            ("enroll-request", "clientCertificateDERBase64", Data(repeating: 0, count: 4097).base64EncodedString() as Any),
            ("enroll-proof", "signatureBase64", Data([0]).base64EncodedString() as Any),
            ("enroll-challenge", "hostChallengeBase64", Data([0]).base64EncodedString() as Any),
            ("enroll-challenge", "encodedWidth", 8193 as Any),
            ("enroll-challenge", "expiresAtUnixMilliseconds", 1724000015001 as Any),
            ("present-request", "nativeGeneration", 0 as Any),
            ("present-request", "nativeGeneration", 9007199254740992 as Any),
            ("present-request", "encodedWidth", 319 as Any),
            ("present-request", "encodedHeight", 8193 as Any),
            ("present-receipt", "inputAdmitted", 1 as Any),
            ("present-receipt", "inputAdmitted", "true" as Any),
            ("present-receipt", "capturePixelWidth", 32769 as Any),
            ("present-receipt", "capturePixelHeight", 0 as Any),
            ("present-receipt", "logicalWidthPoints", 0 as Any),
            ("present-receipt", "logicalHeightPoints", 4294967296 as Any),
            ("ready", "portBase", 1029 as Any), ("ready", "portBase", 65500 as Any)
        ] {
            var record = try JSONSerialization.jsonObject(with: fixture(name)) as! [String: Any]
            var body = record["body"] as! [String: Any]; body[field] = value; record["body"] = body
            XCTAssertThrowsError(try decode(name, JSONSerialization.data(withJSONObject: record)), "\(name): \(field)")
        }
    }
    func testChallengeMaterialMatchesExistingGoldenSigningBytes() throws {
        let challenge = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>.self, from: fixture("enroll-challenge"))
        let preparation = try challenge.body.preparation()
        XCTAssertEqual(preparation.signingInput.base64EncodedString(), challenge.body.signingInputBase64)
        XCTAssertEqual(preparation.hostChallenge.count, 32)
        XCTAssertEqual(preparation.expiresAtUnixMilliseconds - preparation.issuedAtUnixMilliseconds, 15_000)
    }
}
