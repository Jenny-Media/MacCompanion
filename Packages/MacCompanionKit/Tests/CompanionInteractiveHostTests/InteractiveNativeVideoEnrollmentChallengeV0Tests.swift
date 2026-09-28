import Foundation
import XCTest
import CompanionInteractiveShared
@testable import CompanionInteractiveHost

final class InteractiveNativeVideoEnrollmentChallengeV0Tests: XCTestCase {
    private struct Material {
        let binding: InteractiveNativeVideoBindingV0
        let surface: InteractiveNativeVideoSurfaceV0
        let key: Data
        let clientCertificate: Data
        let hostCertificate: Data
        let nonce: Data
        let signature: Data
        let signingInput: Data
        let unixIssue: UInt64
    }

    private func fixture(_ path: String) throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent()
            guard root != parent else { throw CocoaError(.fileNoSuchFile) }
            root = parent
        }
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

    private func material() throws -> Material {
        let scenario = try fixture("valid/native-video-enrollment-admission.json")
        let vector = try fixture(scenario["cryptoFixture"] as! String)
        let fields = vector["inputs"] as! [String: Any]
        let derived = vector["derived"] as! [String: String]
        func id(_ key: String) -> UUID { UUID(uuidString: fields[key] as! String)! }
        func data(_ key: String) -> Data { bytes(fields[key] as! String) }
        func number(_ key: String) -> Int64 { (fields[key] as! NSNumber).int64Value }
        return try Material(binding: .init(hostID: id("hostID"), hostFingerprint: data("hostFingerprintHex"),
            clientID: id("clientID"), primaryConnectionID: data("primaryConnectionIDHex"),
            interactiveSessionID: id("interactiveSessionID"), authorizationEpoch: number("authorizationEpoch"),
            grantRevision: number("grantRevision"), policyRevision: number("policyRevision"),
            controlGeneration: id("streamGeneration"),
            expiresAtMonotonicMilliseconds: (scenario["controlExpiresAtMonotonicMilliseconds"] as! NSNumber).uint64Value),
            surface: .init(surfaceID: id("surfaceID"), surfaceRevision: number("surfaceRevision"),
                coordinateSpaceRevision: number("coordinateSpaceRevision"),
                encodedWidth: Int(number("encodedWidth")), encodedHeight: Int(number("encodedHeight"))),
            key: data("sessionPublicKeyX963Hex"), clientCertificate: data("clientCertificateSHA256Hex"),
            hostCertificate: data("hostCertificateSHA256Hex"), nonce: data("hostChallengeHex"),
            signature: bytes(derived["signatureRawHex"]!), signingInput: bytes(derived["signingInputHex"]!),
            unixIssue: UInt64(number("issuedAtUnixMilliseconds")))
    }

    private func challenge(_ m: Material, nonce: Data? = nil, deadline: UInt64? = nil) throws -> InteractiveNativeVideoEnrollmentChallengeV0 {
        try .init(binding: copyBinding(m.binding, deadline: deadline), surface: m.surface,
            sessionPublicKeyX963: m.key, clientCertificateSHA256: m.clientCertificate,
            hostCertificateSHA256: m.hostCertificate, issuedAtUnixMilliseconds: m.unixIssue,
            issuedAtMonotonicMilliseconds: 1000, conformanceChallenge: nonce ?? m.nonce)
    }

    private func copyBinding(_ b: InteractiveNativeVideoBindingV0, revision: Int64? = nil, deadline: UInt64? = nil) throws -> InteractiveNativeVideoBindingV0 {
        try .init(hostID: b.hostID, hostFingerprint: b.hostFingerprint, clientID: b.clientID,
            primaryConnectionID: b.primaryConnectionID, interactiveSessionID: b.interactiveSessionID,
            authorizationEpoch: b.authorizationEpoch, grantRevision: revision ?? b.grantRevision,
            policyRevision: b.policyRevision, controlGeneration: b.controlGeneration,
            expiresAtMonotonicMilliseconds: deadline ?? b.expiresAtMonotonicMilliseconds)
    }

    func testAuthoritativeSingleUseAndDenialScenarios() throws {
        let m = try material()
        let cases = try fixture("valid/native-video-enrollment-admission.json")["cases"] as! [[String: Any]]
        for scenario in cases {
            let owner = try challenge(m)
            XCTAssertEqual(owner.signingInput, m.signingInput)
            let steps = scenario["steps"] as! [String], expected = scenario["expect"] as! [Bool]
            XCTAssertEqual(steps.count, expected.count)
            for (step, result) in zip(steps, expected) {
                var binding: InteractiveNativeVideoBindingV0? = m.binding
                var surface: InteractiveNativeVideoSurfaceV0? = m.surface
                var key: Data? = m.key
                var signature = m.signature
                var now: UInt64 = 1001
                switch step {
                case "valid": break
                case "badSignature": signature = Data([0])
                case "wrongBinding": binding = try copyBinding(m.binding, revision: m.binding.grantRevision + 1)
                case "wrongSurface": surface = try .init(surfaceID: m.surface.surfaceID,
                    surfaceRevision: m.surface.surfaceRevision + 1,
                    coordinateSpaceRevision: m.surface.coordinateSpaceRevision,
                    encodedWidth: m.surface.encodedWidth, encodedHeight: m.surface.encodedHeight)
                case "wrongKey": key = Data()
                case "missingAuthority": binding = nil; surface = nil; key = nil
                case "expired": now = owner.expiresAtMonotonicMilliseconds
                case "beforeIssue": now = 999
                case "cancel": owner.cancel()
                default: XCTFail("Unknown authoritative step \(step)"); continue
                }
                XCTAssertEqual(owner.consume(rawSignature: signature, currentBinding: binding,
                    currentSurface: surface, currentSessionPublicKeyX963: key,
                    nowMonotonicMilliseconds: now), result, "\(scenario["id"]!): \(step)")
            }
        }
    }

    func testChallengeCannotExtendOriginalControlAndRejectsExpiredIssuance() throws {
        let m = try material(), owner = try challenge(m, deadline: 1010)
        XCTAssertEqual(owner.expiresAtMonotonicMilliseconds, 1010)
        XCTAssertEqual(owner.expiresAtUnixMilliseconds, m.unixIssue + 10)
        XCTAssertNotEqual(owner.signingInput, m.signingInput)
        XCTAssertThrowsError(try challenge(m, deadline: 1000))
        XCTAssertThrowsError(try challenge(m, nonce: Data([1])))
    }

    func testOldAttestationCannotVerifyFreshNonce() throws {
        let m = try material()
        var nonce = m.nonce; nonce[0] ^= 1
        let replacement = try challenge(m, nonce: nonce)
        XCTAssertFalse(replacement.consume(rawSignature: m.signature, currentBinding: m.binding,
            currentSurface: m.surface, currentSessionPublicKeyX963: m.key, nowMonotonicMilliseconds: 1001))
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    func testConcurrentValidAttemptsConsumeExactlyOnce() throws {
        let m = try material(), owner = try challenge(m), count = Counter()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if owner.consume(rawSignature: m.signature, currentBinding: m.binding,
                currentSurface: m.surface, currentSessionPublicKeyX963: m.key, nowMonotonicMilliseconds: 1001) {
                count.increment()
            }
        }
        XCTAssertEqual(count.read(), 1)
    }
}
