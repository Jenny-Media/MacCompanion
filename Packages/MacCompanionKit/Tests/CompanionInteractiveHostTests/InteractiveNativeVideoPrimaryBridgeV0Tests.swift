import Foundation
import XCTest
import CompanionDomain
import CompanionWire
import CompanionInteractiveShared
import CompanionInteractiveWire
@testable import CompanionInteractiveHost

final class InteractiveNativeVideoPrimaryBridgeV0Tests: XCTestCase {
    private func fixture(_ path: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
        }
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
        XCTAssertEqual((index["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count, 1)
        return try Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))
    }
    private struct Material: Sendable {
        let authority: InteractiveNativeVideoAuthorityV0
        let context: InteractiveSessionCommandContextV0
        let request: InteractiveNativeVideoEnrollmentRequestBodyV0
        let proof: InteractiveNativeVideoEnrollmentProofBodyV0
        let challenge: WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>
    }
    private func material() throws -> Material {
        let challenge = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>.self,
            from: fixture("valid/native-video-enroll-challenge.json"))
        let request = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>.self,
            from: fixture("valid/native-video-enroll-request.json")).body
        let proof = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentProofBodyV0>.self,
            from: fixture("valid/native-video-enroll-proof.json")).body
        let crypto = try JSONSerialization.jsonObject(with: fixture("crypto/native-video-enrollment-coordinator-v0.1.json")) as! [String: Any]
        let f = crypto["inputs"] as! [String: Any]
        func bytes(_ s: String) -> Data { let c = Array(s.utf8); return Data(stride(from: 0, to: c.count, by: 2).map { UInt8(String(decoding: c[$0..<$0+2], as: UTF8.self), radix: 16)! }) }
        let host = UUID(uuidString: f["hostID"] as! String)!, client = UUID(uuidString: f["clientID"] as! String)!
        let pin = bytes(f["hostFingerprintHex"] as! String), primary = bytes(f["primaryConnectionIDHex"] as! String), key = bytes(f["sessionPublicKeyX963Hex"] as! String)
        let b = try InteractiveNativeVideoBindingV0(hostID: host, hostFingerprint: pin, clientID: client, primaryConnectionID: primary,
            interactiveSessionID: request.fence.interactiveSessionID.rawValue, authorizationEpoch: 4, grantRevision: 5, policyRevision: 6,
            controlGeneration: challenge.body.controlGeneration.rawValue, expiresAtMonotonicMilliseconds: 60_000)
        let s = try InteractiveNativeVideoSurfaceV0(surfaceID: request.fence.surfaceID.rawValue, surfaceRevision: request.fence.surfaceRevision,
            coordinateSpaceRevision: request.fence.coordinateSpaceRevision, encodedWidth: 1280, encodedHeight: 720)
        let context = try InteractiveSessionCommandContextV0(deviceID: UUID(), clientID: client, deviceState: .activeGranted,
            authorizationEpoch: .init(rawValue: 4), grantRevision: .init(rawValue: 5), policyRevision: .init(rawValue: 6), primaryConnectionID: primary,
            hostID: host, hostFingerprint: pin, hostState: .userSessionActive, wallNowUnixMilliseconds: 1724000000000, monotonicNowMilliseconds: 1000)
        return try .init(authority: .init(binding: b, surface: s, sessionPublicKeyX963: key), context: context, request: request, proof: proof, challenge: challenge)
    }
    private actor Admission: InteractiveSessionAdmissionReadingV0 {
        var value: InteractiveSessionAdmissionSnapshotV0?
        init(_ value: InteractiveSessionAdmissionSnapshotV0) { self.value = value }
        func snapshot(deviceID: UUID) -> InteractiveSessionAdmissionSnapshotV0? { value }
        func revoke() { value = nil }
    }
    private actor NativeRuntime: InteractiveNativeVideoRuntimeProvidingV0 {
        var value: InteractiveNativeVideoRuntimeSnapshotV0
        let backend: Backend
        let gate: Gate?
        var constructions = 0
        init(_ value: InteractiveNativeVideoRuntimeSnapshotV0, backend: Backend, gate: Gate? = nil) {
            self.value = value; self.backend = backend; self.gate = gate
        }
        func snapshot(fence: InteractiveNativeVideoRequestFenceV0, context: InteractiveSessionCommandContextV0) -> InteractiveNativeVideoRuntimeSnapshotV0? { value }
        func makeBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0) async -> any InteractiveNativeVideoEnrollmentBackendV0 {
            constructions += 1
            await gate?.pause()
            return backend
        }
        func count() -> Int { constructions }
        func replaceGeometry(width: UInt32, height: UInt32, rotation: SurfaceRotation) {
            value = .init(binding: value.binding, surface: value.surface, logicalWidthPoints: width,
                logicalHeightPoints: height, rotation: rotation, selectedDisplayID: value.selectedDisplayID,
                visibleMenuAppGeneration: value.visibleMenuAppGeneration, visibleMenuAppRevision: value.visibleMenuAppRevision)
        }
    }
    private func admission(_ m: Material, display: UUID, menu: UUID, revision: UInt64 = 1) throws -> InteractiveSessionAdmissionSnapshotV0 {
        try .init(deviceID: m.context.deviceID, clientID: m.context.clientID, deviceState: .activeGranted,
            authorizationEpoch: m.context.authorizationEpoch, grantRevision: m.context.grantRevision,
            policyRevision: m.context.policyRevision, approvalPublicKeyX963: m.authority.sessionPublicKeyX963,
            grants: CapabilityGrantSet([InteractiveControlCapabilityV0.identifier]), deviceDisplayName: DeviceDisplayName("Test phone"),
            visibleMenuAppAvailable: true, visibleMenuAppGeneration: menu, visibleMenuAppRevision: revision,
            selectedDisplayID: display, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
    }
    func testStoreBoundFactoryKeepsActivityAndPublicationRevisionsIndependent() async throws {
        let vectors = try JSONSerialization.jsonObject(with: fixture("local-xpc-native-runtime-snapshot-v0.1.json")) as! [String: Any]
        for row in vectors["independentRevisionCases"] as! [[String: Any]] {
            let admissionRevision = (row["publicationRevision"] as! NSNumber).uint64Value
            let runtimeRevision = (row["activityRevision"] as! NSNumber).uint64Value
            let accepted = row["accepted"] as! Bool
            let m = try material(), display = UUID(), menu = UUID()
            let a = Admission(try admission(m, display: display, menu: menu, revision: admissionRevision))
            let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!)
            let runtime = NativeRuntime(.init(binding: m.authority.binding, surface: m.authority.surface,
                logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0,
                selectedDisplayID: display,
                visibleMenuAppGeneration: row["menuGenerationMatches"] as! Bool ? menu : UUID(),
                visibleMenuAppRevision: runtimeRevision), backend: b)
            let owner = InteractiveNativeVideoRuntimeCompositionV0(admission: a, runtime: runtime,
                monotonicMilliseconds: { 1000 }, unixMilliseconds: { 1724000000000 }).bridge()
            do {
                _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID,
                    context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
                XCTAssertTrue(accepted, "Zero activity revision or wrong menu generation was accepted")
            } catch {
                XCTAssertFalse(accepted, "Independent current activity/publication counters were rejected")
            }
            let count = await runtime.count()
            XCTAssertEqual(count, accepted ? 1 : 0)
            await owner.close(interactiveSessionID: m.authority.binding.interactiveSessionID)
        }
    }
    func testStoreBoundFactoryRejectsRuntimeDisplayMismatchBeforeBackendConstruction() async throws {
        let m = try material(), display = UUID(), menu = UUID()
        let a = Admission(try admission(m, display: display, menu: menu))
        let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!)
        let runtime = NativeRuntime(.init(binding: m.authority.binding, surface: m.authority.surface,
            logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0, selectedDisplayID: UUID(), visibleMenuAppGeneration: menu, visibleMenuAppRevision: 1), backend: b)
        let owner = InteractiveNativeVideoRuntimeCompositionV0(admission: a, runtime: runtime,
            monotonicMilliseconds: { 1000 }, unixMilliseconds: { 1724000000000 }).bridge()
        do { _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID,
            context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Different display admitted") } catch {}
        let count = await runtime.count(); XCTAssertEqual(count, 0)
    }
    func testStoreBoundFactoryRechecksGrantAfterBackendConstruction() async throws {
        let m = try material(), display = UUID(), menu = UUID(), gate = Gate()
        let a = Admission(try admission(m, display: display, menu: menu))
        let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!)
        let runtime = NativeRuntime(.init(binding: m.authority.binding, surface: m.authority.surface,
            logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0, selectedDisplayID: display, visibleMenuAppGeneration: menu, visibleMenuAppRevision: 1), backend: b, gate: gate)
        let owner = InteractiveNativeVideoRuntimeCompositionV0(admission: a, runtime: runtime,
            monotonicMilliseconds: { 1000 }, unixMilliseconds: { 1724000000000 }).bridge()
        let preparing = Task { try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID,
            context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963) }
        try await wait(gate)
        await a.revoke()
        await gate.release()
        do { _ = try await preparing.value; XCTFail("Revoked construction admitted") } catch {}
        let counts = await b.counts(); XCTAssertEqual(counts.0, 0)
    }
    func testStoreBoundFactoryRejectsLogicalGeometryChangesDuringConstruction() async throws {
        for (width, height, rotation) in [(UInt32(2561), UInt32(1440), SurfaceRotation.degrees0),
                                         (2560, 1441, .degrees0), (2560, 1440, .degrees90)] {
            let m = try material(), display = UUID(), menu = UUID(), gate = Gate()
            let a = Admission(try admission(m, display: display, menu: menu))
            let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!)
            let runtime = NativeRuntime(.init(binding: m.authority.binding, surface: m.authority.surface,
                logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0,
                selectedDisplayID: display, visibleMenuAppGeneration: menu, visibleMenuAppRevision: 1), backend: b, gate: gate)
            let owner = InteractiveNativeVideoRuntimeCompositionV0(admission: a, runtime: runtime,
                monotonicMilliseconds: { 1000 }, unixMilliseconds: { 1724000000000 }).bridge()
            let preparing = Task { try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID,
                context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963) }
            try await wait(gate)
            await runtime.replaceGeometry(width: width, height: height, rotation: rotation)
            await gate.release()
            do { _ = try await preparing.value; XCTFail("Changed logical geometry admitted") } catch {}
            let counts = await b.counts(); XCTAssertEqual(counts.0, 0)
        }
    }
    func testStoreBoundCoordinatorDrainsWhenDurableGrantDisappears() async throws {
        let m = try material(), display = UUID(), menu = UUID()
        let a = Admission(try admission(m, display: display, menu: menu))
        let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!)
        let runtime = NativeRuntime(.init(binding: m.authority.binding, surface: m.authority.surface,
            logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0, selectedDisplayID: display, visibleMenuAppGeneration: menu, visibleMenuAppRevision: 1), backend: b)
        let owner = InteractiveNativeVideoRuntimeCompositionV0(admission: a, runtime: runtime,
            monotonicMilliseconds: { 1000 }, unixMilliseconds: { 1724000000000 }).bridge()
        _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID,
            context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        await a.revoke()
        for _ in 0..<100 {
            if await b.counts().1 > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let counts = await b.counts(); XCTAssertEqual(counts.1, 1)
        await owner.close(interactiveSessionID: m.authority.binding.interactiveSessionID)
    }
    private actor Gate {
        var arrived = false, open = false
        var continuation: CheckedContinuation<Void, Never>?
        func pause() async { arrived = true; if !open { await withCheckedContinuation { continuation = $0 } } }
        func release() { open = true; continuation?.resume(); continuation = nil }
        func waiting() -> Bool { arrived }
    }
    private actor Backend: InteractiveNativeVideoEnrollmentBackendV0 {
        let der: Data, gate: Gate?
        let sample: Data?, captureGate: Gate?
        var retired = false, starts = 0, drains = 0
        init(_ der: Data, gate: Gate? = nil, sample: Data? = nil, captureGate: Gate? = nil) {
            self.der = der; self.gate = gate; self.sample = sample; self.captureGate = captureGate
        }
        func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async throws -> Data { der }
        func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 { starts += 1; await gate?.pause(); return try .init(portBase: 58989) }
        func isActive(operationID: UUID) async -> Bool { starts > 0 && !retired }
        func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? {
            await captureGate?.pause()
            guard let sample else { return nil }
            let fixture = try JSONSerialization.jsonObject(with: sample) as! [String: Any]
            var record = fixture["record"] as! [String: Any]
            record["operationID"] = operationID.uuidString; record["monotonicNanoseconds"] = 1_000_000_000
            record["encodedWidth"] = 1280; record["formatWidth"] = 1280; record["cleanWidth"] = 1280
            record["encodedHeight"] = 720; record["formatHeight"] = 720; record["cleanHeight"] = 720
            return try .decode(JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
        func retire(operationID: UUID) async { retired = true; drains += 1; await gate?.release(); await captureGate?.release() }
        func counts() -> (Int, Int) { (starts, drains) }
    }
    private func bridge(_ m: Material, backend: Backend, construction: Gate? = nil) -> InteractiveNativeVideoPrimaryBridgeV0 {
        .init { _, _, _ in
            await construction?.pause()
            return .init(authority: m.authority, backend: backend, readAuthority: { m.authority }, monotonicMilliseconds: { 1000 },
                unixMilliseconds: { m.challenge.body.issuedAtUnixMilliseconds }, conformanceChallenge: Data(base64Encoded: m.challenge.body.hostChallengeBase64),
                logicalWidthPoints: 2560, logicalHeightPoints: 1440, monotonicNanoseconds: { 1_000_000_000 })
        }
    }
    private func wait(_ gate: Gate) async throws {
        for _ in 0..<100 { if await gate.waiting() { return }; try await Task.sleep(for: .milliseconds(2)) }
        XCTFail("Bridge did not reach expected suspension")
    }
    func testIndexedGoldenProofPreparesActivatesAndCancelsExactlyOnce() async throws {
        let m = try material(), b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!), owner = bridge(m, backend: b)
        let prepared = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        XCTAssertEqual(prepared, m.challenge.body)
        let ready = try await owner.activate(m.proof, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        XCTAssertEqual(ready.portBase, 58989)
        try await owner.cancel(m.request.fence, context: m.context)
        try await owner.cancel(m.request.fence, context: m.context)
        let counts = await b.counts(); XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testStopJoinsPendingFactoryAndSuppressesLateChallenge() async throws {
        let m = try material(), gate = Gate(), b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!), owner = bridge(m, backend: b, construction: gate)
        let preparing = Task { try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963) }
        try await wait(gate)
        let stopping = Task { try await owner.cancel(m.request.fence, context: m.context) }
        try await Task.sleep(for: .milliseconds(10))
        await gate.release()
        try await stopping.value
        do { _ = try await preparing.value; XCTFail("Late challenge escaped Stop") } catch {}
        let counts = await b.counts(); XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 1)
    }
    func testMismatchedChallengeConsumesCurrentAttempt() async throws {
        let m = try material(), b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!), owner = bridge(m, backend: b)
        _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        let wrong = try InteractiveNativeVideoEnrollmentProofBodyV0(fence: m.proof.fence, challengeMessageID: WireUUID(UUID()), signatureBase64: m.proof.signatureBase64)
        do { _ = try await owner.activate(wrong, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Wrong correlation admitted") } catch {}
        do { _ = try await owner.activate(m.proof, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Proof replayed after failed attempt") } catch {}
        let counts = await b.counts(); XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 1)
    }
    func testParallelProofDoesNotCancelReservedLaunch() async throws {
        let m = try material(), gate = Gate(), b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!, gate: gate), owner = bridge(m, backend: b)
        _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        let launching = Task { try await owner.activate(m.proof, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963) }
        try await wait(gate)
        do { _ = try await owner.activate(m.proof, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Parallel proof admitted") } catch {}
        await gate.release()
        _ = try await launching.value
        try await owner.cancel(m.request.fence, context: m.context)
        let counts = await b.counts(); XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testPresentationRequiresActiveExactChallengeAndOneRendererGeneration() async throws {
        let m = try material()
        let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!,
            sample: try fixture("valid/native-backend-capture-evidence.json")), owner = bridge(m, backend: b)
        let request = try InteractiveNativeVideoPresentationRequestBodyV0(fence: m.request.fence,
            challengeMessageID: m.challenge.messageID, nativeGeneration: 1, encodedWidth: 1280, encodedHeight: 720)
        do { _ = try await owner.present(request, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Presentation before enrollment") } catch {}
        _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        _ = try await owner.activate(m.proof, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        let wrongChallenge = try InteractiveNativeVideoPresentationRequestBodyV0(fence: m.request.fence,
            challengeMessageID: WireUUID(UUID()), nativeGeneration: 1, encodedWidth: 1280, encodedHeight: 720)
        do { _ = try await owner.present(wrongChallenge, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Wrong challenge admitted") } catch {}
        let receipt = try await owner.present(request, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        XCTAssertEqual(receipt.nativeGeneration, 1); XCTAssertEqual(receipt.capturePixelWidth, 5120)
        XCTAssertEqual(receipt.logicalWidthPoints, 2560); XCTAssertEqual(receipt.logicalHeightPoints, 1440)
        let replacement = try InteractiveNativeVideoPresentationRequestBodyV0(fence: m.request.fence,
            challengeMessageID: m.challenge.messageID, nativeGeneration: 2, encodedWidth: 1280, encodedHeight: 720)
        do { _ = try await owner.present(replacement, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Replacement renderer admitted") } catch {}
        try await owner.cancel(m.request.fence, context: m.context)
        do { _ = try await owner.present(request, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Retired presentation admitted") } catch {}
    }

    func testCancellationAndParallelPresentationCannotReleaseSuspendedReceipt() async throws {
        let m = try material(), gate = Gate()
        let b = Backend(Data(base64Encoded: m.challenge.body.hostCertificateDERBase64)!,
            sample: try fixture("valid/native-backend-capture-evidence.json"), captureGate: gate), owner = bridge(m, backend: b)
        _ = try await owner.prepare(m.request, challengeMessageID: m.challenge.messageID, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        _ = try await owner.activate(m.proof, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963)
        let request = try InteractiveNativeVideoPresentationRequestBodyV0(fence: m.request.fence,
            challengeMessageID: m.challenge.messageID, nativeGeneration: 1, encodedWidth: 1280, encodedHeight: 720)
        let work = Task { try await owner.present(request, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963) }
        try await wait(gate)
        do { _ = try await owner.present(request, context: m.context, sessionPublicKeyX963: m.authority.sessionPublicKeyX963); XCTFail("Concurrent presentation admitted") } catch {}
        try await owner.cancel(m.request.fence, context: m.context)
        do { _ = try await work.value; XCTFail("Late receipt escaped cancellation") } catch {}
        let counts = await b.counts(); XCTAssertEqual(counts.1, 1)
    }

}
