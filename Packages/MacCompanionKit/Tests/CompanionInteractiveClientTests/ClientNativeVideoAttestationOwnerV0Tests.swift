import Foundation
import XCTest
import CompanionClient
import CompanionInteractiveShared
@testable import CompanionInteractiveClient

final class ClientNativeVideoAttestationOwnerV0Tests: XCTestCase {
    private struct Material: Sendable {
        let authority: ClientNativeVideoAttestationAuthorityV0
        let clientDER: Data
        let preparation: InteractiveNativeVideoEnrollmentPreparationV0
        let signature: Data
    }
    private func material() throws -> Material {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
        }
        let path = "crypto/native-video-enrollment-coordinator-v0.1.json"
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
        XCTAssertEqual((manifest["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count, 1)
        let f = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
        let v = f["inputs"] as! [String: Any], d = f["derived"] as! [String: String], cert = f["certificateConformanceBytes"] as! [String: String]
        func bytes(_ s: String) -> Data { let c = Array(s.utf8); return Data(stride(from: 0, to: c.count, by: 2).map { UInt8(String(decoding: c[$0..<$0+2], as: UTF8.self), radix: 16)! }) }
        func id(_ k: String) -> UUID { UUID(uuidString: v[k] as! String)! }
        func n(_ k: String) -> Int64 { (v[k] as! NSNumber).int64Value }
        let b = try InteractiveNativeVideoBindingV0(hostID: id("hostID"), hostFingerprint: bytes(v["hostFingerprintHex"] as! String), clientID: id("clientID"),
            primaryConnectionID: bytes(v["primaryConnectionIDHex"] as! String), interactiveSessionID: id("interactiveSessionID"), authorizationEpoch: n("authorizationEpoch"),
            grantRevision: n("grantRevision"), policyRevision: n("policyRevision"), controlGeneration: id("streamGeneration"), expiresAtMonotonicMilliseconds: 60_000)
        let s = try InteractiveNativeVideoSurfaceV0(surfaceID: id("surfaceID"), surfaceRevision: n("surfaceRevision"), coordinateSpaceRevision: n("coordinateSpaceRevision"),
            encodedWidth: Int(n("encodedWidth")), encodedHeight: Int(n("encodedHeight")))
        return try Material(authority: .init(binding: b, surface: s, sessionPublicKeyX963: bytes(v["sessionPublicKeyX963Hex"] as! String)), clientDER: bytes(cert["clientHex"]!),
            preparation: .init(hostCertificateDER: bytes(cert["hostHex"]!), signingInput: bytes(d["signingInputHex"]!), hostChallenge: bytes(v["hostChallengeHex"] as! String),
                issuedAtUnixMilliseconds: UInt64(n("issuedAtUnixMilliseconds")), expiresAtUnixMilliseconds: UInt64(n("expiresAtUnixMilliseconds"))), signature: bytes(d["signatureRawHex"]!))
    }
    private final class Clock: @unchecked Sendable {
        let lock = NSLock(); var value: UInt64 = 1000
        func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ v: UInt64) { lock.lock(); value = v; lock.unlock() }
    }
    private actor Authority {
        var value: ClientNativeVideoAttestationAuthorityV0?
        init(_ v: ClientNativeVideoAttestationAuthorityV0) { value = v }
        func read() -> ClientNativeVideoAttestationAuthorityV0? { value }
        func revoke() { value = nil }
    }
    private actor Signer: ClientSessionAuthenticationSigningV0 {
        let expected: Data, signature: Data
        var hold = false, calls = 0
        var waiter: CheckedContinuation<Void, Never>?
        init(_ m: Material) { expected = m.preparation.signingInput; signature = m.signature }
        func pause() { hold = true }
        func count() -> Int { calls }
        func release() { waiter?.resume(); waiter = nil }
        func signAuthenticationInput(_ input: Data) async throws -> Data {
            calls += 1
            XCTAssertEqual(input, expected)
            if hold { await withCheckedContinuation { waiter = $0 } }
            return signature
        }
    }
    private func owner(_ m: Material, _ signer: Signer, _ authority: Authority, _ clock: Clock,
                       validate: Bool = true) throws -> ClientNativeVideoAttestationOwnerV0 {
        try .init(authority: m.authority, clientCertificateDER: m.clientDER, signer: signer,
            readAuthority: { await authority.read() }, validateCertificate: { _ in validate }, monotonicMilliseconds: { clock.read() })
    }
    private func wait(_ signer: Signer) async throws {
        for _ in 0..<100 { if await signer.count() == 1 { return }; try await Task.sleep(for: .milliseconds(2)) }
        XCTFail("Signer did not reach suspension")
    }
    func testSignsReconstructedGoldenInputOnce() async throws {
        let m = try material(), s = Signer(m), a = Authority(m.authority), c = Clock(), o = try owner(m, s, a, c)
        let signature = try await o.attest(m.preparation)
        XCTAssertEqual(signature, m.signature)
        do { _ = try await o.attest(m.preparation); XCTFail("Duplicate attestation") } catch {}
        let calls = await s.count(), phase = await o.phase
        XCTAssertEqual(calls, 1); XCTAssertEqual(phase, .complete)
    }
    func testChangedHostMaterialAndRejectedCertificateNeverReachCustody() async throws {
        let m = try material()
        for invalidCertificate in [true, false] {
            let s = Signer(m), a = Authority(m.authority), c = Clock(), o = try owner(m, s, a, c, validate: !invalidCertificate)
            let p = m.preparation
            let changed = try InteractiveNativeVideoEnrollmentPreparationV0(hostCertificateDER: p.hostCertificateDER + Data([0]), signingInput: p.signingInput,
                hostChallenge: p.hostChallenge, issuedAtUnixMilliseconds: p.issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: p.expiresAtUnixMilliseconds)
            do { _ = try await o.attest(invalidCertificate ? p : changed); XCTFail("Invalid material signed") } catch {}
            let calls = await s.count(); XCTAssertEqual(calls, 0)
        }
    }
    func testStopRevocationAndSigningExpiryDiscardLateCustodyResult() async throws {
        let m = try material()
        for event in ["stop", "revoke", "expiry", "rollback"] {
            let s = Signer(m), a = Authority(m.authority), c = Clock(), o = try owner(m, s, a, c)
            await s.pause()
            let signing = Task { try await o.attest(m.preparation) }
            try await wait(s)
            switch event {
            case "stop": await o.retire()
            case "revoke": await a.revoke()
            case "expiry": c.set(16_000)
            default: c.set(999)
            }
            await s.release()
            do { _ = try await signing.value; XCTFail("Late signature escaped \(event)") } catch {}
            let phase = await o.phase; XCTAssertEqual(phase, .retired)
        }
    }
    func testClosedPreparationBounds() throws {
        let p = try material().preparation
        XCTAssertThrowsError(try InteractiveNativeVideoEnrollmentPreparationV0(hostCertificateDER: Data(), signingInput: p.signingInput,
            hostChallenge: p.hostChallenge, issuedAtUnixMilliseconds: p.issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: p.expiresAtUnixMilliseconds))
        XCTAssertThrowsError(try InteractiveNativeVideoEnrollmentPreparationV0(hostCertificateDER: p.hostCertificateDER, signingInput: p.signingInput,
            hostChallenge: Data(), issuedAtUnixMilliseconds: p.issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: p.expiresAtUnixMilliseconds))
    }
}
