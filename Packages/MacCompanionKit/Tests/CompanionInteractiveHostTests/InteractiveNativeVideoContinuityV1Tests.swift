import Foundation
import XCTest
import CompanionDomain
import CompanionWire
import CompanionInteractiveWire
import CompanionInteractiveShared
@testable import CompanionInteractiveHost

final class InteractiveNativeVideoContinuityV1Tests: XCTestCase {
    private func fixture(_ path: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
        XCTAssertEqual((manifest["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count, 1)
        return try Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))
    }
    private struct Material: Sendable {
        let authority: InteractiveNativeVideoAuthorityV0
        let request: InteractiveNativeVideoEnrollmentRequestBodyV0
        let challenge: WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>
        let proof: InteractiveNativeVideoEnrollmentProofBodyV0
    }
    private func material(replacement: Bool) throws -> Material {
        let f = try JSONSerialization.jsonObject(with: fixture("native-stream-continuity-v0.1.json")) as! [String: Any]
        let records = f["wireRecords"] as! [String: Any]
        func record(_ name: String) throws -> Data {
            replacement ? try JSONSerialization.data(withJSONObject: records[name]!) : try fixture("valid/native-video-\(name).json")
        }
        let decoded = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>.self, from: record("enroll-request")).body
        let request = try InteractiveNativeVideoEnrollmentRequestBodyV0(fence: decoded.fence,
            clientCertificateDERBase64: decoded.clientCertificateDERBase64,
            previousFence: decoded.previousFence, streamContinuity: true)
        let challenge = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>.self, from: record("enroll-challenge"))
        let proof = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentProofBodyV0>.self, from: record("enroll-proof")).body
        let crypto = try JSONSerialization.jsonObject(with: fixture("crypto/native-video-enrollment-coordinator-v0.1.json")) as! [String: Any]
        let v = crypto["inputs"] as! [String: Any]
        func bytes(_ field: String) -> Data {
            let chars = Array((v[field] as! String).utf8)
            return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(decoding: chars[$0..<$0+2], as: UTF8.self), radix: 16)! })
        }
        let binding = try InteractiveNativeVideoBindingV0(hostID: UUID(uuidString: v["hostID"] as! String)!,
            hostFingerprint: bytes("hostFingerprintHex"), clientID: UUID(uuidString: v["clientID"] as! String)!,
            primaryConnectionID: bytes("primaryConnectionIDHex"), interactiveSessionID: request.fence.interactiveSessionID.rawValue,
            authorizationEpoch: 4, grantRevision: 5, policyRevision: 6,
            controlGeneration: challenge.body.controlGeneration.rawValue, expiresAtMonotonicMilliseconds: 60_000)
        let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: request.fence.surfaceID.rawValue,
            surfaceRevision: request.fence.surfaceRevision, coordinateSpaceRevision: request.fence.coordinateSpaceRevision,
            encodedWidth: 1280, encodedHeight: 720)
        return try .init(authority: .init(binding: binding, surface: surface, sessionPublicKeyX963: bytes("sessionPublicKeyX963Hex")),
            request: request, challenge: challenge, proof: proof)
    }
    private final class Clock: @unchecked Sendable {
        let lock = NSLock(); private var now: UInt64 = 1000
        func read() -> UInt64 { lock.withLock { now } }
        func set(_ value: UInt64) { lock.withLock { now = value } }
    }
    private actor Admission {
        var value: InteractiveNativeVideoAuthorityV0?
        let original: InteractiveNativeVideoAuthorityV0
        var granted = true
        init(_ authority: InteractiveNativeVideoAuthorityV0) { value = authority; original = authority }
        func surface(_ expected: InteractiveNativeVideoAuthorityV0) -> InteractiveNativeVideoAuthorityV0? { granted && value == expected ? value : nil }
        func control() -> Bool { granted }
        func select(_ authority: InteractiveNativeVideoAuthorityV0) { value = authority }
        func revoke() { granted = false; value = nil }
    }
    /// Models one physical process and certificate, with exact logical owners.
    /// No socket, capture permission or input effects are used by this double.
    private actor Backend: InteractiveNativeVideoEnrollmentBackendV0 {
        let der: Data, sample: Data
        var operation: UUID?, retained = false, active = false, retired = false
        var starts = 0, drains = 0, input = false, supported = true
        var holdRetain = false, retaining = false, waiter: CheckedContinuation<Void, Never>?
        init(der: Data, sample: Data) { self.der = der; self.sample = sample }
        func configure(supported: Bool = true, holdRetain: Bool = false) { self.supported = supported; self.holdRetain = holdRetain }
        func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) throws -> Data {
            guard !retired, operation == nil || retained else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
            operation = operationID; active = false; input = false
            return der
        }
        func activate(operationID: UUID) throws -> InteractiveNativeVideoEndpointV0 {
            guard operation == operationID, !retired else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
            if starts == 0 { starts = 1 }
            active = true; retained = false
            return try .init(portBase: 58989)
        }
        func isActive(operationID: UUID) -> Bool { operation == operationID && active && !retired && !retained }
        func supportsStreamContinuity(operationID: UUID) -> Bool { supported && isActive(operationID: operationID) }
        func retainStream(operationID: UUID) async throws {
            guard isActive(operationID: operationID) else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
            retaining = true; input = false; active = false; retained = true
            if holdRetain { await withCheckedContinuation { waiter = $0 } }
        }
        func isStreamRetained(operationID: UUID) -> Bool { operation == operationID && retained && !retired }
        func captureEvidence(operationID: UUID) throws -> InteractiveNativeVideoCaptureEvidenceV0? {
            guard isActive(operationID: operationID) else { return nil }
            let fixture = try JSONSerialization.jsonObject(with: sample) as! [String: Any]
            var record = fixture["record"] as! [String: Any]
            record["operationID"] = operationID.uuidString; record["monotonicNanoseconds"] = 1_000_000_000
            record["encodedWidth"] = 1280; record["formatWidth"] = 1280; record["cleanWidth"] = 1280
            record["encodedHeight"] = 720; record["formatHeight"] = 720; record["cleanHeight"] = 720
            return try .decode(JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
        func admitPresentation(operationID: UUID, nativeGeneration: Int64, presentationID: UUID) -> Bool {
            input = isActive(operationID: operationID); return input
        }
        func retire(operationID: UUID) {
            guard operation == nil || operation == operationID, !retired else { return }
            retired = true; active = false; retained = false; input = false; drains += 1
            waiter?.resume(); waiter = nil
        }
        func status() -> (starts: Int, drains: Int, input: Bool, retaining: Bool) { (starts, drains, input, retaining) }
    }
    private func context(_ m: Material) throws -> InteractiveSessionCommandContextV0 {
        let b = m.authority.binding
        return try .init(deviceID: UUID(), clientID: b.clientID, deviceState: .activeGranted,
            authorizationEpoch: .init(rawValue: 4), grantRevision: .init(rawValue: 5), policyRevision: .init(rawValue: 6),
            primaryConnectionID: b.primaryConnectionID, hostID: b.hostID, hostFingerprint: b.hostFingerprint,
            hostState: .userSessionActive, wallNowUnixMilliseconds: 1724000000000, monotonicNowMilliseconds: 1000)
    }
    private func bridge(_ old: Material, _ next: Material, _ b: Backend, _ a: Admission, _ clock: Clock) -> InteractiveNativeVideoPrimaryBridgeV0 {
        @Sendable func coordinator(_ m: Material, predecessor: InteractiveNativeVideoRetainedEnrollmentV1? = nil) -> InteractiveNativeVideoEnrollmentCoordinatorV0 {
            .init(authority: m.authority, backend: b, readAuthority: { await a.surface(m.authority) },
                monotonicMilliseconds: { clock.read() }, unixMilliseconds: { m.challenge.body.issuedAtUnixMilliseconds },
                conformanceChallenge: Data(base64Encoded: m.challenge.body.hostChallengeBase64), logicalWidthPoints: 2560,
                logicalHeightPoints: 1440, monotonicNanoseconds: { 1_000_000_000 },
                readRetainedAuthority: { await a.control() }, predecessor: predecessor)
        }
        return .init(factory: { _, _, _ in coordinator(old) }, replacementFactory: { _, _, _, retained in coordinator(next, predecessor: retained) })
    }
    private func present(_ m: Material, owner: InteractiveNativeVideoPrimaryBridgeV0,
        context: InteractiveSessionCommandContextV0, generation: Int64) async throws {
        _ = try await owner.present(.init(fence: m.request.fence, challengeMessageID: m.challenge.messageID,
            nativeGeneration: generation, encodedWidth: 1280, encodedHeight: 720),
            context: context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
    }
    private func enrolled(_ old: Material, _ next: Material, _ b: Backend, _ a: Admission, _ clock: Clock,
        _ c: InteractiveSessionCommandContextV0) async throws -> InteractiveNativeVideoPrimaryBridgeV0 {
        let owner = bridge(old, next, b, a, clock)
        let challenge = try await owner.prepare(old.request, challengeMessageID: old.challenge.messageID,
            context: c, sessionPublicKeyX963: old.authority.sessionPublicKeyX963)
        XCTAssertEqual(challenge, old.challenge.body)
        let ready = try await owner.activate(old.proof, context: c, sessionPublicKeyX963: old.authority.sessionPublicKeyX963)
        let supported = await b.supportsStreamContinuity(operationID: UUID()) // Wrong owner cannot advertise.
        XCTAssertFalse(supported)
        XCTAssertNotNil(ready.portBase)
        try await present(old, owner: owner, context: c, generation: 1)
        return owner
    }
    func testGoldenReplacementRetainsProcessAndRequiresFreshPresentation() async throws {
        let old = try material(replacement: false), next = try material(replacement: true), c = try context(old), clock = Clock()
        let b = Backend(der: Data(base64Encoded: old.challenge.body.hostCertificateDERBase64)!, sample: try fixture("valid/native-backend-capture-evidence.json")), a = Admission(old.authority)
        let owner = try await enrolled(old, next, b, a, clock, c)
        let retained = try await owner.retain(old.request.fence, context: c); XCTAssertTrue(retained)
        let retried = try await owner.retain(old.request.fence, context: c); XCTAssertTrue(retried)
        var status = await b.status(); XCTAssertFalse(status.input); XCTAssertEqual(status.drains, 0)
        await a.select(next.authority)
        let challenge = try await owner.prepare(next.request, challengeMessageID: next.challenge.messageID,
            context: c, sessionPublicKeyX963: next.authority.sessionPublicKeyX963)
        XCTAssertEqual(challenge, next.challenge.body)
        let ready = try await owner.activate(next.proof, context: c, sessionPublicKeyX963: next.authority.sessionPublicKeyX963)
        XCTAssertEqual(ready.streamContinuity, true)
        status = await b.status(); XCTAssertEqual(status.starts, 1); XCTAssertFalse(status.input)
        do { try await owner.cancel(old.request.fence, context: c); XCTFail("Old cancellation admitted") } catch {}
        do {
            _ = try await owner.prepare(old.request, challengeMessageID: old.challenge.messageID, context: c,
                sessionPublicKeyX963: old.authority.sessionPublicKeyX963)
            XCTFail("Old enrollment replay admitted")
        } catch {}
        do {
            _ = try await owner.prepare(next.request, challengeMessageID: next.challenge.messageID, context: c,
                sessionPublicKeyX963: next.authority.sessionPublicKeyX963)
            XCTFail("Replacement replay admitted")
        } catch {}
        status = await b.status(); XCTAssertEqual(status.drains, 0)
        try await present(next, owner: owner, context: c, generation: 2)
        status = await b.status(); XCTAssertTrue(status.input)
        await owner.close(interactiveSessionID: next.authority.binding.interactiveSessionID)
        status = await b.status(); XCTAssertEqual(status.drains, 1)
    }
    func testOldGoldenProofCannotActivateReplacement() async throws {
        let old = try material(replacement: false), next = try material(replacement: true), c = try context(old), clock = Clock()
        let b = Backend(der: Data(base64Encoded: old.challenge.body.hostCertificateDERBase64)!, sample: try fixture("valid/native-backend-capture-evidence.json")), a = Admission(old.authority)
        let owner = try await enrolled(old, next, b, a, clock, c)
        _ = try await owner.retain(old.request.fence, context: c)
        await a.select(next.authority)
        _ = try await owner.prepare(next.request, challengeMessageID: next.challenge.messageID, context: c, sessionPublicKeyX963: next.authority.sessionPublicKeyX963)
        let replay = try InteractiveNativeVideoEnrollmentProofBodyV0(fence: next.proof.fence,
            challengeMessageID: next.proof.challengeMessageID, signatureBase64: old.proof.signatureBase64)
        do { _ = try await owner.activate(replay, context: c, sessionPublicKeyX963: next.authority.sessionPublicKeyX963); XCTFail("Old proof admitted") } catch {}
        let status = await b.status(); XCTAssertEqual(status.starts, 1); XCTAssertEqual(status.drains, 1); XCTAssertFalse(status.input)
    }
    func testRetainedExpiryRevocationAndMissingPredecessorDrain() async throws {
        for loss in ["expiry", "revocation", "predecessor"] {
            let old = try material(replacement: false), next = try material(replacement: true), c = try context(old), clock = Clock()
            let b = Backend(der: Data(base64Encoded: old.challenge.body.hostCertificateDERBase64)!, sample: try fixture("valid/native-backend-capture-evidence.json")), a = Admission(old.authority)
            let owner = try await enrolled(old, next, b, a, clock, c)
            _ = try await owner.retain(old.request.fence, context: c)
            if loss == "expiry" { clock.set(16_000) }
            else if loss == "revocation" { await a.revoke() }
            else {
                let missing = try InteractiveNativeVideoEnrollmentRequestBodyV0(fence: next.request.fence,
                    clientCertificateDERBase64: next.request.clientCertificateDERBase64)
                do { _ = try await owner.prepare(missing, challengeMessageID: next.challenge.messageID, context: c,
                    sessionPublicKeyX963: next.authority.sessionPublicKeyX963); XCTFail("Missing predecessor admitted") } catch {}
            }
            let retained = await owner.hasRetainedStream(context: c); XCTAssertFalse(retained)
            let status = await b.status(); XCTAssertEqual(status.drains, 1); XCTAssertFalse(status.input)
        }
    }
    func testStopWhileRetainSuspendedCannotExposeLateRetainedReply() async throws {
        let old = try material(replacement: false), next = try material(replacement: true), c = try context(old), clock = Clock()
        let b = Backend(der: Data(base64Encoded: old.challenge.body.hostCertificateDERBase64)!, sample: try fixture("valid/native-backend-capture-evidence.json")), a = Admission(old.authority)
        let owner = try await enrolled(old, next, b, a, clock, c)
        await b.configure(holdRetain: true)
        let work = Task { try await owner.retain(old.request.fence, context: c) }
        for _ in 0..<100 { if await b.status().retaining { break }; try await Task.sleep(for: .milliseconds(2)) }
        let status = await b.status(); XCTAssertTrue(status.retaining)
        try await owner.cancel(old.request.fence, context: c)
        do { _ = try await work.value; XCTFail("Late retain reply escaped Stop") } catch {}
        let final = await b.status(); XCTAssertEqual(final.drains, 1); XCTAssertFalse(final.input)
    }
    func testUnsupportedBackendUsesFullCancellation() async throws {
        let old = try material(replacement: false), next = try material(replacement: true), c = try context(old), clock = Clock()
        let b = Backend(der: Data(base64Encoded: old.challenge.body.hostCertificateDERBase64)!, sample: try fixture("valid/native-backend-capture-evidence.json")), a = Admission(old.authority)
        await b.configure(supported: false)
        let owner = try await enrolled(old, next, b, a, clock, c)
        let retained = try await owner.retain(old.request.fence, context: c); XCTAssertFalse(retained)
        let status = await b.status(); XCTAssertEqual(status.drains, 1)
    }

    func testLegacyClientNeverReceivesUnrequestedCapability() async throws {
        let old = try material(replacement: false), next = try material(replacement: true), c = try context(old), clock = Clock()
        let b = Backend(der: Data(base64Encoded: old.challenge.body.hostCertificateDERBase64)!, sample: try fixture("valid/native-backend-capture-evidence.json")), a = Admission(old.authority)
        let owner = bridge(old, next, b, a, clock)
        let legacy = try InteractiveNativeVideoEnrollmentRequestBodyV0(fence: old.request.fence,
            clientCertificateDERBase64: old.request.clientCertificateDERBase64)
        _ = try await owner.prepare(legacy, challengeMessageID: old.challenge.messageID, context: c,
            sessionPublicKeyX963: old.authority.sessionPublicKeyX963)
        let ready = try await owner.activate(old.proof, context: c, sessionPublicKeyX963: old.authority.sessionPublicKeyX963)
        XCTAssertNil(ready.streamContinuity)
        try await present(old, owner: owner, context: c, generation: 1)
        let retained = try await owner.retain(old.request.fence, context: c); XCTAssertFalse(retained)
        let status = await b.status(); XCTAssertEqual(status.drains, 1)
    }
}
