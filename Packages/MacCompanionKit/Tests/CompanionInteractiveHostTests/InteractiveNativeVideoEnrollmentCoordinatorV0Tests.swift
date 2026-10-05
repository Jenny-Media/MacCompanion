import Foundation
import XCTest
import CompanionInteractiveShared
@testable import CompanionInteractiveHost

final class InteractiveNativeVideoEnrollmentCoordinatorV0Tests: XCTestCase {
    private struct Material: Sendable {
        let authority: InteractiveNativeVideoAuthorityV0
        let clientDER: Data
        let hostDER: Data
        let signature: Data
        let nonce: Data
        let signingInput: Data
        let unix: UInt64
    }
    private func material() throws -> Material {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw CocoaError(.fileNoSuchFile) }
            root = parent
        }
        let path = "crypto/native-video-enrollment-coordinator-v0.1.json"
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
        XCTAssertEqual((manifest["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count, 1)
        let f = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
        let v = f["inputs"] as! [String: Any], d = f["derived"] as! [String: String]
        func bytes(_ s: String) -> Data {
            let chars = Array(s.utf8)
            return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(decoding: chars[$0..<$0+2], as: UTF8.self), radix: 16)! })
        }
        func id(_ k: String) -> UUID { UUID(uuidString: v[k] as! String)! }
        func n(_ k: String) -> Int64 { (v[k] as! NSNumber).int64Value }
        let b = try InteractiveNativeVideoBindingV0(hostID: id("hostID"), hostFingerprint: bytes(v["hostFingerprintHex"] as! String),
            clientID: id("clientID"), primaryConnectionID: bytes(v["primaryConnectionIDHex"] as! String), interactiveSessionID: id("interactiveSessionID"),
            authorizationEpoch: n("authorizationEpoch"), grantRevision: n("grantRevision"), policyRevision: n("policyRevision"),
            controlGeneration: id("streamGeneration"), expiresAtMonotonicMilliseconds: 60_000)
        let s = try InteractiveNativeVideoSurfaceV0(surfaceID: id("surfaceID"), surfaceRevision: n("surfaceRevision"),
            coordinateSpaceRevision: n("coordinateSpaceRevision"), encodedWidth: Int(n("encodedWidth")), encodedHeight: Int(n("encodedHeight")))
        let cert = f["certificateConformanceBytes"] as! [String: String]
        return try Material(authority: .init(binding: b, surface: s, sessionPublicKeyX963: bytes(v["sessionPublicKeyX963Hex"] as! String)),
            clientDER: bytes(cert["clientHex"]!), hostDER: bytes(cert["hostHex"]!), signature: bytes(d["signatureRawHex"]!),
            nonce: bytes(v["hostChallengeHex"] as! String), signingInput: bytes(d["signingInputHex"]!), unix: UInt64(n("issuedAtUnixMilliseconds")))
    }
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt64 = 1000
        func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ value: UInt64) { lock.lock(); self.value = value; lock.unlock() }
    }
    private actor Authority {
        var value: InteractiveNativeVideoAuthorityV0?
        init(_ value: InteractiveNativeVideoAuthorityV0) { self.value = value }
        func read() -> InteractiveNativeVideoAuthorityV0? { value }
        func revoke() { value = nil }
    }
    private actor Backend: InteractiveNativeVideoEnrollmentBackendV0 {
        let hostDER: Data
        var holdPrepare = false, holdActivate = false, holdDrain = false
        var preparing = false, activating = false, retired = false
        var starts = 0, drains = 0
        var captureMode = "valid", holdCapture = false, capturing = false
        var pendingCaptureReads = 0, captureReads = 0
        func delayCapture(reads: Int) { pendingCaptureReads = reads }
        func captureReadCount() -> Int { captureReads }
        var inputAdmission = false, holdPresentation = false, presenting = false
        func presentationSettings(admitted: Bool, hold: Bool = false) { inputAdmission = admitted; holdPresentation = hold }
        func presentationStarted() -> Bool { presenting }
        func admitPresentation(operationID: UUID, nativeGeneration: Int64, presentationID: UUID) async -> Bool {
            presenting = true
            if holdPresentation { await withCheckedContinuation { waiter = $0 } }
            return inputAdmission
        }
        var preparedSurface: InteractiveNativeVideoSurfaceV0?
        var waiter: CheckedContinuation<Void, Never>?
        var drainWaiter: CheckedContinuation<Void, Never>?
        init(_ hostDER: Data) { self.hostDER = hostDER }
        func hold(preparation: Bool = false, activation: Bool = false) { holdPrepare = preparation; holdActivate = activation }
        func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async throws -> Data {
            guard !retired else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
            preparing = true
            preparedSurface = authority.surface
            if holdPrepare { await withCheckedContinuation { waiter = $0 } }
            // Deliberately return even after retirement: tests prove the coordinator
            // never exposes late results from a misbehaving asynchronous backend.
            return hostDER
        }
        func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
            guard !retired else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
            starts += 1; activating = true
            if holdActivate { await withCheckedContinuation { waiter = $0 } }
            return try .init(portBase: 57989)
        }
        func release() { waiter?.resume(); waiter = nil }
        func isActive(operationID: UUID) async -> Bool { starts > 0 && !retired }
        func captureSettings(mode: String = "valid", hold: Bool = false) { captureMode = mode; holdCapture = hold }
        func captureStarted() -> Bool { capturing }
        func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? {
            capturing = true
            captureReads += 1
            if holdCapture { await withCheckedContinuation { waiter = $0 } }
            if pendingCaptureReads > 0 { pendingCaptureReads -= 1; return nil }
            if captureMode == "pending" { return nil }
            var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
                let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
            }
            let path = "valid/native-backend-capture-evidence.json"
            let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
            guard (index["fixtures"] as! [[String: Any]]).filter({ $0["path"] as? String == path }).count == 1 else { throw CocoaError(.fileNoSuchFile) }
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
            var record = fixture["record"] as! [String: Any]
            record["operationID"] = (captureMode == "wrongOperation" ? UUID() : operationID).uuidString
            record["monotonicNanoseconds"] = captureMode == "future" ? 1_000_000_001 : 1_000_000_000
            let surface = preparedSurface!
            record["encodedWidth"] = surface.encodedWidth; record["encodedHeight"] = surface.encodedHeight
            record["formatWidth"] = surface.encodedWidth; record["formatHeight"] = surface.encodedHeight
            record["cleanWidth"] = surface.encodedWidth; record["cleanHeight"] = surface.encodedHeight
            return try .decode(JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
        func crash() { retired = true }
        func holdRetirement() { holdDrain = true }
        func releaseRetirement() { drainWaiter?.resume(); drainWaiter = nil }
        func retire(operationID: UUID) async {
            retired = true; drains += 1; release()
            if holdDrain { await withCheckedContinuation { drainWaiter = $0 } }
        }
        func counts() -> (Int, Int) { (starts, drains) }
        func waiting(activation: Bool) -> Bool { activation ? activating : preparing }
    }
    private func owner(_ m: Material, _ b: Backend, _ a: Authority, _ c: Clock) -> InteractiveNativeVideoEnrollmentCoordinatorV0 {
        .init(authority: m.authority, backend: b, readAuthority: { await a.read() },
              monotonicMilliseconds: { c.read() }, unixMilliseconds: { m.unix }, conformanceChallenge: m.nonce,
              logicalWidthPoints: 2560, logicalHeightPoints: 1067,
              monotonicNanoseconds: { c.read() * 1_000_000 })
    }
    private func wait(_ backend: Backend, activation: Bool) async throws {
        for _ in 0..<100 {
            if await backend.waiting(activation: activation) { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Backend did not reach expected suspension")
    }
    func testGoldenEnrollmentActivatesOnceAndJoinsRetirement() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock()
        let o = owner(m, b, a, c), challenge = try await o.prepare(clientCertificateDER: m.clientDER)
        XCTAssertEqual(challenge.signingInput, m.signingInput)
        let endpoint = try await o.activate(rawSignature: m.signature)
        XCTAssertEqual(endpoint.portBase, 57989)
        do { _ = try await o.activate(rawSignature: m.signature); XCTFail("Replayed proof") } catch {}
        async let first: Void = o.retire()
        async let second: Void = o.retire()
        _ = await (first, second)
        let counts = await b.counts(), phase = await o.phase
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1); XCTAssertEqual(phase, .retired)
    }
    func testInvalidProofNeverStartsAndCannotBeRetried() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        do { _ = try await o.activate(rawSignature: Data([0])); XCTFail("Invalid proof") } catch {}
        do { _ = try await o.activate(rawSignature: m.signature); XCTFail("Retry after failed proof") } catch {}
        let counts = await b.counts()
        XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 1)
    }
    func testStopDuringPreparationRejectsLateCertificate() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        await b.hold(preparation: true)
        let work = Task { try await o.prepare(clientCertificateDER: m.clientDER) }
        try await wait(b, activation: false)
        await o.retire()
        do { _ = try await work.value; XCTFail("Late preparation escaped Stop") } catch {}
        let counts = await b.counts()
        XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 1)
    }
    func testRevocationDuringActivationCompensatesWithoutEndpoint() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        await b.hold(activation: true)
        let work = Task { try await o.activate(rawSignature: m.signature) }
        try await wait(b, activation: true)
        await a.revoke(); await b.release()
        do { _ = try await work.value; XCTFail("Revoked endpoint escaped") } catch {}
        let counts = await b.counts(), phase = await o.phase
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1); XCTAssertEqual(phase, .retired)
    }
    func testExpiryDuringActivationCannotExtendSignedChallenge() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        await b.hold(activation: true)
        let work = Task { try await o.activate(rawSignature: m.signature) }
        try await wait(b, activation: true)
        c.set(16_000); await b.release()
        do { _ = try await work.value; XCTFail("Expired activation escaped") } catch {}
        let counts = await b.counts(); XCTAssertEqual(counts.1, 1)
    }
    func testParallelProofDoesNotCancelReservedActivation() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        await b.hold(activation: true)
        let work = Task { try await o.activate(rawSignature: m.signature) }
        try await wait(b, activation: true)
        do { _ = try await o.activate(rawSignature: m.signature); XCTFail("Parallel proof") } catch {}
        await b.release()
        _ = try await work.value
        let counts = await b.counts(); XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 0)
        await o.retire()
    }
    func testWatchdogRetiresWithoutFurtherTraffic() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        _ = try await o.activate(rawSignature: m.signature)
        await a.revoke()
        for _ in 0..<100 {
            if await o.phase == .retired { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let phase = await o.phase, counts = await b.counts()
        XCTAssertEqual(phase, .retired); XCTAssertEqual(counts.1, 1)
    }
    func testMalformedCertificateAndClockRollbackRetireBeforeStartup() async throws {
        let m = try material()
        for malformed in [true, false] {
            let b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
            if !malformed { c.set(999) }
            do { _ = try await o.prepare(clientCertificateDER: malformed ? Data() : m.clientDER); XCTFail("Invalid preparation") } catch {}
            let counts = await b.counts(); XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 1)
        }
    }
    func testRevocationRefreshJoinsAlreadyRunningProcessDrain() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        _ = try await o.activate(rawSignature: m.signature)
        await b.holdRetirement()
        let stopping = Task { await o.retire() }
        for _ in 0..<100 {
            if await b.counts().1 == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let finished = Clock()
        let refresh = Task { let result = await o.refreshAuthority(); finished.set(1); return result }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(finished.read(), 1000, "Revocation returned before drain")
        await b.releaseRetirement()
        await stopping.value
        let result = await refresh.value, phase = await o.phase
        XCTAssertFalse(result); XCTAssertEqual(phase, .retired)
    }

    func testUnexpectedHelperExitRetiresStillApprovedSession() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        _ = try await o.activate(rawSignature: m.signature)
        await b.crash()
        let healthy = await o.refreshAuthority(), phase = await o.phase, counts = await b.counts()
        XCTAssertFalse(healthy); XCTAssertEqual(phase, .retired); XCTAssertEqual(counts.1, 1)
    }

    func testPresentationUsesCurrentActualSampleAndOriginalGeometry() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        _ = try await o.activate(rawSignature: m.signature)
        let evidence = try await o.presentationEvidence(encodedWidth: m.authority.surface.encodedWidth,
            encodedHeight: m.authority.surface.encodedHeight)
        XCTAssertEqual(evidence.capturePixelWidth, 5120)
        let logicalWidth = await o.logicalWidthPoints, logicalHeight = await o.logicalHeightPoints
        XCTAssertEqual(logicalWidth, 2560)
        XCTAssertEqual(logicalHeight, 1067)
        let phase = await o.phase; XCTAssertEqual(phase, .active)
        await o.retire()
    }

    func testPendingWrongOperationFutureAndStaleSamplesCannotProduceReceipt() async throws {
        for mode in ["pending", "wrongOperation", "future", "stale"] {
            let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
            _ = try await o.prepare(clientCertificateDER: m.clientDER)
            _ = try await o.activate(rawSignature: m.signature)
            await b.captureSettings(mode: mode)
            if mode == "stale" { c.set(3001) }
            do { _ = try await o.presentationEvidence(encodedWidth: m.authority.surface.encodedWidth,
                encodedHeight: m.authority.surface.encodedHeight); XCTFail("Invalid sample admitted: \(mode)") } catch {}
            let phase = await o.phase, counts = await b.counts()
            XCTAssertEqual(phase, .retired); XCTAssertEqual(counts.1, 1)
        }
    }

    func testDelayedFirstCaptureObservationDoesNotRestartOrRetireBackend() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        _ = try await o.activate(rawSignature: m.signature)
        await b.delayCapture(reads: 4)
        let evidence = try await o.presentationEvidence(encodedWidth: m.authority.surface.encodedWidth,
            encodedHeight: m.authority.surface.encodedHeight)
        XCTAssertEqual(evidence.capturePixelWidth, 5120)
        let counts = await b.counts(), phase = await o.phase
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 0); XCTAssertEqual(phase, .active)
        await o.retire()
    }

    func testLossWhileWaitingForFirstObservationNeverReturnsPresentation() async throws {
        for loss in ["stop", "revocation", "expiry", "backend"] {
            let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
            _ = try await o.prepare(clientCertificateDER: m.clientDER)
            _ = try await o.activate(rawSignature: m.signature)
            await b.captureSettings(mode: "pending")
            let work = Task { try await o.presentationEvidence(encodedWidth: m.authority.surface.encodedWidth,
                encodedHeight: m.authority.surface.encodedHeight) }
            for _ in 0..<100 { if await b.captureReadCount() >= 2 { break }; try await Task.sleep(for: .milliseconds(2)) }
            let reads = await b.captureReadCount(); XCTAssertGreaterThanOrEqual(reads, 2)
            switch loss {
            case "stop": await o.retire()
            case "revocation": await a.revoke()
            case "expiry": c.set(60_000)
            default: await b.crash()
            }
            do { _ = try await work.value; XCTFail("Pending observation escaped \(loss)") } catch {}
            let counts = await b.counts(), phase = await o.phase
            XCTAssertEqual(counts.1, 1); XCTAssertEqual(phase, .retired)
        }
    }

    func testSampleReadFinishingAfterPendingDeadlineCannotAdmitPresentation() async throws {
        let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
        _ = try await o.prepare(clientCertificateDER: m.clientDER)
        _ = try await o.activate(rawSignature: m.signature)
        await b.captureSettings(hold: true)
        let work = Task { try await o.presentationEvidence(encodedWidth: m.authority.surface.encodedWidth,
            encodedHeight: m.authority.surface.encodedHeight) }
        for _ in 0..<100 { if await b.captureStarted() { break }; try await Task.sleep(for: .milliseconds(2)) }
        let started = await b.captureStarted(); XCTAssertTrue(started)
        try await Task.sleep(for: .milliseconds(2100))
        await b.release()
        do { _ = try await work.value; XCTFail("Late sample escaped pending deadline") } catch {}
        let phase = await o.phase, counts = await b.counts()
        XCTAssertEqual(phase, .retired); XCTAssertEqual(counts.1, 1)
    }

    func testStopRevocationAndBackendLossDuringSampleReadSuppressLateReceipt() async throws {
        for loss in ["stop", "revocation", "backend"] {
            let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
            _ = try await o.prepare(clientCertificateDER: m.clientDER)
            _ = try await o.activate(rawSignature: m.signature)
            await b.captureSettings(hold: true)
            let work = Task { try await o.presentationEvidence(encodedWidth: m.authority.surface.encodedWidth,
                encodedHeight: m.authority.surface.encodedHeight) }
            for _ in 0..<100 { if await b.captureStarted() { break }; try await Task.sleep(for: .milliseconds(2)) }
            let started = await b.captureStarted(); XCTAssertTrue(started)
            if loss == "stop" { await o.retire() }
            else if loss == "revocation" { await a.revoke() }
            else { await b.crash() }
            await b.release()
            do { _ = try await work.value; XCTFail("Late receipt escaped \(loss)") } catch {}
            let phase = await o.phase; XCTAssertEqual(phase, .retired)
        }
    }

    func testPresentationReceiptRetainsExplicitBackendInputAdmission() async throws {
        for admitted in [false, true] {
            let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
            _ = try await o.prepare(clientCertificateDER: m.clientDER)
            _ = try await o.activate(rawSignature: m.signature)
            await b.presentationSettings(admitted: admitted)
            let presentation = try await o.acknowledgePresentation(encodedWidth: m.authority.surface.encodedWidth,
                encodedHeight: m.authority.surface.encodedHeight, nativeGeneration: 1, presentationID: UUID())
            XCTAssertEqual(presentation.inputAdmitted, admitted)
            await o.retire()
        }
    }
    func testInputInstallationCannotReturnLateAdmissionAfterStopAuthorityBackendOrSampleLoss() async throws {
        for loss in ["stop", "authority", "backend", "stale"] {
            let m = try material(), b = Backend(m.hostDER), a = Authority(m.authority), c = Clock(), o = owner(m, b, a, c)
            _ = try await o.prepare(clientCertificateDER: m.clientDER)
            _ = try await o.activate(rawSignature: m.signature)
            await b.presentationSettings(admitted: true, hold: true)
            let work = Task { try await o.acknowledgePresentation(encodedWidth: m.authority.surface.encodedWidth,
                encodedHeight: m.authority.surface.encodedHeight, nativeGeneration: 1, presentationID: UUID()) }
            for _ in 0..<100 { if await b.presentationStarted() { break }; try await Task.sleep(for: .milliseconds(2)) }
            let started = await b.presentationStarted(); XCTAssertTrue(started)
            if loss == "stop" { await o.retire() }
            else if loss == "authority" { await a.revoke() }
            else if loss == "backend" { await b.crash() }
            else { c.set(4_000) }
            await b.release()
            do { _ = try await work.value; XCTFail("Late input admission escaped") } catch {}
            let phase = await o.phase; XCTAssertEqual(phase, .retired)
        }
    }

}
