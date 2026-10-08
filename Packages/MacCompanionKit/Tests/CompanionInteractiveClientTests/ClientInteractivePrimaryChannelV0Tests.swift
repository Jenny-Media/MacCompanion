@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Testing

private actor InteractivePrimaryTransportV0:
    ClientAuthenticatedCommandSendingV1
{
    private(set) var frames: [Data] = []
    private var rejectNext = false
    private var suspendNext = false
    private var resumeSuspended: CheckedContinuation<Void, Never>?
    private(set) var sendIsSuspended = false
    enum Failure: Error { case injected }
    func rejectNextSend() { rejectNext = true }
    func suspendNextSend() { suspendNext = true }
    func resumeSend() {
        sendIsSuspended = false
        resumeSuspended?.resume()
        resumeSuspended = nil
    }

    func sendAuthenticatedCommand(_ frame: Data) async throws {
        if rejectNext { rejectNext = false; throw Failure.injected }
        frames.append(frame)
        if suspendNext {
            suspendNext = false
            sendIsSuspended = true
            await withCheckedContinuation { resumeSuspended = $0 }
        }
    }
}

private final class InteractivePrimaryEventRecorderV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: [ClientInteractivePrimarySessionEventV0] = []

    var events: [ClientInteractivePrimarySessionEventV0] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: ClientInteractivePrimarySessionEventV0) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private final class InteractivePrimaryFocusRecorderV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: [ClientSurfaceFocusEventV0] = []

    var events: [ClientSurfaceFocusEventV0] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: ClientSurfaceFocusEventV0) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private struct InteractivePrimarySignerV0:
    ClientInteractiveApprovalSigningV0
{
    func signSessionChallenge(_ input: Data) async throws -> Data {
        Data(repeating: 0x66, count: 64)
    }
}

private struct FailingInteractivePrimarySignerV0:
    ClientInteractiveApprovalSigningV0
{
    func signSessionChallenge(_ input: Data) async throws -> Data {
        _ = input
        throw InteractivePrimaryCustodyErrorV0.unsupported
    }
}

private enum InteractivePrimaryCustodyErrorV0: Error {
    case unsupported
}

private actor InteractivePrimaryCustodyV0: ClientIdentityKeyCustodyV0 {
    private(set) var approvalReasons: [ClientApprovalPresenceReasonV0] = []
    private(set) var sessionReferences: [ClientSigningKeyReferenceV0] = []

    func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        throw InteractivePrimaryCustodyErrorV0.unsupported
    }

    func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool { false }

    func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data {
        sessionReferences.append(reference)
        return Data(repeating: 0x55, count: 64)
    }

    func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data {
        approvalReasons.append(reason)
        return Data(repeating: 0x99, count: 64)
    }

    func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws {}
}

private final class NativePrimaryClockV0: @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64 = 10_000
    func now() -> UInt64 { lock.lock(); defer { lock.unlock() }; return time }
    func advance(to value: UInt64) { lock.lock(); defer { lock.unlock() }; time = value }
}

private struct InteractivePrimaryHarnessV0 {
    let clock: NativePrimaryClockV0
    let host: ClientDurablePairedHostV0
    let session: ClientAuthenticatedSessionV0
    let transport: InteractivePrimaryTransportV0
    let router: ClientPrimaryCommandRouterV0
    let channel: ClientInteractivePrimaryChannelV0
    let events: InteractivePrimaryEventRecorderV0
    let focusEvents: InteractivePrimaryFocusRecorderV0
}

private func interactivePrimaryHarness(
    signer: any ClientInteractiveApprovalSigningV0 =
        InteractivePrimarySignerV0()
) async throws
    -> InteractivePrimaryHarnessV0
{
    let pairingID = UUID()
    let clientID = UUID()
    let hostID = UUID()
    let deviceID = UUID()
    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let host = try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: pairingID,
            clientID: clientID,
            hostID: hostID,
            deviceID: deviceID,
            hostFingerprint: Data(repeating: 0x55, count: 32),
            endpoints: [try EndpointCandidate(
                kind: .dns,
                value: "control.example.test",
                port: 47_474
            )],
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 1)
        ),
        identity: try ClientPreparedIdentityV0(
            pairingID: pairingID,
            clientID: clientID,
            sessionKey: ClientCustodiedPublicKeyV0(
                role: .session,
                reference: ClientSigningKeyReferenceV0(UUID()),
                publicKeyX963: sessionKey.publicKey.x963Representation,
                protection: .afterFirstUnlockThisDeviceOnly
            ),
            approvalKey: ClientCustodiedPublicKeyV0(
                role: .approval,
                reference: ClientSigningKeyReferenceV0(UUID()),
                publicKeyX963: approvalKey.publicKey.x963Representation,
                protection: .whenUnlockedThisDeviceOnlyUserPresence
            )
        )
    )
    let session = ClientAuthenticatedSessionV0(
        clientID: clientID,
        hostID: hostID,
        deviceID: deviceID,
        connectionID: Data(repeating: 0x11, count: 16),
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 5),
        policyRevision: .init(rawValue: 6),
        hostState: .userSessionActive,
        features: [],
        serverTimeUnixMilliseconds: 1_000
    )
    let clock = NativePrimaryClockV0()
    let transport = InteractivePrimaryTransportV0()
    let router = try ClientPrimaryCommandRouterV0(
        authenticatedSession: session,
        transport: transport,
        monotonicNowNanoseconds: { clock.now() * 1_000_000 }
    )
    let events = InteractivePrimaryEventRecorderV0()
    let focusEvents = InteractivePrimaryFocusRecorderV0()
    let channel = try ClientInteractivePrimaryChannelV0(
        pairedHost: host,
        authenticatedSession: session,
        signer: signer,
        sender: router.sender(for: .control),
        environment: ClientInteractivePrimaryEnvironmentV0(
            makeMessageID: { WireUUID(UUID()) },
            wallNowUnixMilliseconds: { 1_002 },
            monotonicNowMilliseconds: { clock.now() }
        ),
        publish: { events.record($0) },
        publishFocus: { focusEvents.record($0) }
    )
    try await router.installReceiver(channel, for: .control)
    try await router.activate()
    return InteractivePrimaryHarnessV0(
        clock: clock,
        host: host,
        session: session,
        transport: transport,
        router: router,
        channel: channel,
        events: events,
        focusEvents: focusEvents
    )
}

@Test func interactivePrimarySelectDisplayAcceptsReplyBeforeSendCompletes()
    async throws
{
    let harness = try await interactivePrimaryHarness()
    let displayID = UUID()
    await harness.transport.suspendNextSend()
    let selecting = Task {
        try await harness.channel.selectDisplay(
            displayID,
            expectedAdmissionRevision: 1,
            timeoutMilliseconds: 500
        )
    }
    defer {
        selecting.cancel()
        Task { await harness.transport.resumeSend() }
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while await harness.transport.sendIsSuspended == false,
          ContinuousClock.now < deadline { await Task.yield() }
    try #require(await harness.transport.sendIsSuspended)
    let frame = try #require(await harness.transport.frames.last)
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveDisplaySelectBodyV1>.self,
        from: frame
    )
    try await harness.router.receive(WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: request.messageID,
        sentAtUnixMilliseconds: 1_003,
        body: try InteractiveDisplaySelectedBodyV1(
            authorizationEpoch: harness.session.authorizationEpoch,
            admissionRevision: 2,
            selectedDisplayID: WireUUID(displayID)
        )
    )))
    await harness.transport.resumeSend()
    #expect(try await selecting.value.selectedDisplayID.rawValue == displayID)
    #expect(await harness.router.state == .ready)
}

private func interactivePrimaryChallenge(
    harness: InteractivePrimaryHarnessV0,
    requestID: WireUUID,
    effects: Set<InteractiveControlEffect>
) throws -> WireEnvelope<InteractiveApprovalChallengeBody> {
    try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveApprovalChallengeBody(
            hostID: WireUUID(harness.session.hostID),
            hostFingerprint: WireFingerprint(
                harness.host.hostFingerprint
            ),
            clientID: WireUUID(harness.session.clientID),
            primaryConnectionID: WireBytes16(
                harness.session.connectionID
            ),
            requestID: requestID,
            approvalID: WireUUID(UUID()),
            serverChallenge: WireBytes32(Data(repeating: 0x44, count: 32)),
            authorizationEpoch: harness.session.authorizationEpoch,
            grantRevision: harness.session.grantRevision,
            policyRevision: harness.session.policyRevision,
            selectedDisplayID: WireUUID(UUID()),
            initialSurface: .desktop,
            effects: effects,
            issuedAtUnixMilliseconds: 1_001,
            expiresAtUnixMilliseconds: 61_001
        )
    )
}

private func interactivePrimaryAccepted(
    harness: InteractivePrimaryHarnessV0,
    proofID: WireUUID,
    lifetime: Int64 = InteractiveSessionStateMachine.maximumDurationMilliseconds
) throws -> WireEnvelope<InteractiveSessionAcceptedBody> {
    try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proofID,
        sentAtUnixMilliseconds: 2_000,
        body: try InteractiveSessionAcceptedBody(
            interactiveSessionID: WireUUID(UUID()),
            authorizationEpoch: harness.session.authorizationEpoch,
            expiresAtUnixMilliseconds: 2_000 + lifetime,
            inputChannel: InteractiveChannelOffer(
                channelID: WireUUID(UUID()),
                role: .input,
                credential: WireBytes32(Data(repeating: 0x77, count: 32)),
                issuedAtUnixMilliseconds: 2_000,
                expiresAtUnixMilliseconds: 32_000
            ),
            mediaChannel: InteractiveChannelOffer(
                channelID: WireUUID(UUID()),
                role: .media,
                credential: WireBytes32(Data(repeating: 0x88, count: 32)),
                issuedAtUnixMilliseconds: 2_000,
                expiresAtUnixMilliseconds: 32_000
            )
        )
    )
}

private func interactivePrimarySDP(_ byte: String) -> String {
    let fingerprint = Array(repeating: byte, count: 32).joined(separator: ":")
    return "v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\ns=-\r\nt=0 0\r\n"
        + "a=fingerprint:sha-256 \(fingerprint)\r\n"
        + "a=candidate:1 1 udp 1 192.0.2.1 5000 typ host\r\n"
        + "a=end-of-candidates\r\n"
}

@Test func desktopTunnelCancellationRetiresLateAcceptanceWithoutPublishingUsableSession() async throws {
    let harness = try await interactivePrimaryHarness()
    let effects: Set<InteractiveControlEffect> = [.view, .pointer, .keyboard]
    _ = try await harness.channel.beginSession(effects: effects)
    let request = try WireCodec.decode(WireEnvelope<InteractiveSessionRequestBody>.self,
        from: try #require(await harness.transport.frames.first))
    await harness.channel.retireSessionRequest()
    try await harness.router.receive(WireCodec.encode(try interactivePrimaryChallenge(harness: harness,
        requestID: request.messageID, effects: effects)))
    let proof = try WireCodec.decode(WireEnvelope<InteractiveApprovalProofBody>.self,
        from: try #require(await harness.transport.frames.last))
    let accepted = try interactivePrimaryAccepted(harness: harness, proofID: proof.messageID)
    try await harness.router.receive(WireCodec.encode(accepted))
    let end = try WireCodec.decode(WireEnvelope<InteractiveSessionEndBodyV0>.self,
        from: try #require(await harness.transport.frames.last))
    #expect(end.body.interactiveSessionID == accepted.body.interactiveSessionID)
    #expect(!harness.events.events.contains { if case .accepted = $0 { return true }; return false })
    #expect(await harness.router.state == .ready)
    await #expect(throws: (any Error).self) { try await harness.channel.beginSession(effects: effects) }
}

private func nativePrimaryFixture<B: WireBody>(_ name: String, as type: B.Type) throws -> WireEnvelope<B> {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
    }
    let path = "valid/native-video-\(name).json"
    let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
    #expect((index["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count == 1)
    return try WireCodec.decode(WireEnvelope<B>.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path)))
}

private func nativePrimarySentFrame(_ harness: InteractivePrimaryHarnessV0, kind: WireMessageKind, excluding: WireUUID? = nil) async throws -> Data {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        if let frame = await harness.transport.frames.last, try WireCodec.messageKind(from: frame) == kind,
           try WireCodec.routingMetadata(from: frame).messageID != excluding { return frame }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw ClientInteractivePrimaryChannelErrorV0.unavailable
}

private struct NativeUnexpectedSigner: ClientSessionAuthenticationSigningV0 {
    func signAuthenticationInput(_ input: Data) async throws -> Data {
        Issue.record("Cancelled enrollment reached signing")
        throw ClientInteractivePrimaryChannelErrorV0.unavailable
    }
}

private actor NativeCertificateValidationGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var entered = false
    func wait() async -> Bool {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(returning: true); continuation = nil }
}

private actor NativeDrainCompletion {
    private(set) var finished = false
    func finish() { finished = true }
}

private func verifyRetiredNativeEnrollmentCannotCancelReplacement(
    _ harness: InteractivePrimaryHarnessV0, descriptor: AdaptiveSurfaceDescriptor
) async throws {
    let template = try nativePrimaryFixture("enroll-challenge", as: InteractiveNativeVideoEnrollmentChallengeBodyV0.self)
    let certificate = try nativePrimaryFixture("enroll-request", as: InteractiveNativeVideoEnrollmentRequestBodyV0.self)
    let der = try #require(Data(base64Encoded: certificate.body.clientCertificateDERBase64))
    let gate = NativeCertificateValidationGate()
    let owner = ClientNativeVideoEnrollmentSessionV0(channel: harness.channel, signer: NativeUnexpectedSigner(),
        validateCertificate: { _ in await gate.wait() }, monotonicMilliseconds: { 3000 })
    let attempt = Task { try await owner.enroll(descriptor: descriptor, clientCertificateDER: der) }
    let request = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeEnrollRequest))
    func challenge(for request: WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>) throws
        -> WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0> {
        let t = template.body
        return try WireEnvelope(messageID: WireUUID(UUID()), correlationID: request.messageID, sentAtUnixMilliseconds: 2_001,
            body: InteractiveNativeVideoEnrollmentChallengeBodyV0(fence: request.body.fence, controlGeneration: t.controlGeneration,
                encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight,
                hostCertificateDERBase64: t.hostCertificateDERBase64, hostChallengeBase64: t.hostChallengeBase64,
                signingInputBase64: t.signingInputBase64, issuedAtUnixMilliseconds: t.issuedAtUnixMilliseconds,
                expiresAtUnixMilliseconds: t.expiresAtUnixMilliseconds))
    }
    try await harness.router.receive(WireCodec.encode(challenge(for: request)))
    let validationDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !(await gate.entered), ContinuousClock.now < validationDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await gate.entered)
    let completion = NativeDrainCompletion()
    let closing = Task { await owner.close(); await completion.finish() }
    let cancel = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeCancel))
    #expect(cancel.body.fence == request.body.fence)
    try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: cancel.messageID,
        sentAtUnixMilliseconds: 2_002, body: try InteractiveNativeVideoCancelledBodyV0(fence: cancel.body.fence))))
    try await harness.channel.cancelNativeEnrollment()
    // The canceled certificate validator deliberately ignores task cancellation.
    // A fresh reservation can exist while the old owner joins that validator.
    let replacement = Task { try await harness.channel.requestNativeEnrollment(for: descriptor, clientCertificateDER: der) }
    let replacementRequest = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeEnrollRequest, excluding: request.messageID))
    await gate.release()
    var staleCancel: WireEnvelope<InteractiveNativeVideoCancelBodyV0>?
    let closeDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !(await completion.finished), ContinuousClock.now < closeDeadline {
        if let frame = await harness.transport.frames.last, try WireCodec.messageKind(from: frame) == .nativeCancel {
            let candidate = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self, from: frame)
            if candidate.body.fence == replacementRequest.body.fence { staleCancel = candidate; break }
        }
        try await Task.sleep(for: .milliseconds(1))
    }
    if let staleCancel {
        // Unblock the broken implementation so failure evidence includes cleanup.
        try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: staleCancel.messageID,
            sentAtUnixMilliseconds: 2_003, body: try InteractiveNativeVideoCancelledBodyV0(fence: staleCancel.body.fence))))
    }
    await closing.value
    do { _ = try await attempt.value; Issue.record("Retired certificate attempt completed") } catch {}
    #expect(staleCancel == nil, "Retired enrollment compensation canceled the replacement's exact fence")
    if staleCancel != nil { _ = try? await replacement.value; return }
    let freshChallenge = try challenge(for: replacementRequest)
    try await harness.router.receive(WireCodec.encode(freshChallenge))
    #expect(try await replacement.value == freshChallenge)
    #expect(await harness.channel.nativeAttestationAuthority(for: freshChallenge) != nil)
    let cleanup = Task { try await harness.channel.cancelNativeEnrollment() }
    let cleanupRequest = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeCancel, excluding: cancel.messageID))
    try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: cleanupRequest.messageID,
        sentAtUnixMilliseconds: 2_004, body: try InteractiveNativeVideoCancelledBodyV0(fence: cleanupRequest.body.fence))))
    try await cleanup.value
    #expect(await harness.router.state == .ready)
}

private func verifyNativePrimaryRouting(_ harness: InteractivePrimaryHarnessV0, descriptor: AdaptiveSurfaceDescriptor, continuity: Bool = false) async throws {
    let template = try nativePrimaryFixture("enroll-challenge", as: InteractiveNativeVideoEnrollmentChallengeBodyV0.self)
    let requestTemplate = try nativePrimaryFixture("enroll-request", as: InteractiveNativeVideoEnrollmentRequestBodyV0.self)
    let ownerID = UUID()
    let requestTask = Task { try await harness.channel.requestNativeEnrollment(for: descriptor,
        clientCertificateDER: Data(base64Encoded: requestTemplate.body.clientCertificateDERBase64)!, localOwnerID: ownerID,
        streamContinuity: continuity, timeoutMilliseconds: 1000) }
    let request = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeEnrollRequest))
    let t = template.body
    let challenge = try WireEnvelope(messageID: WireUUID(UUID()), correlationID: request.messageID, sentAtUnixMilliseconds: 2_001,
        body: InteractiveNativeVideoEnrollmentChallengeBodyV0(fence: request.body.fence, controlGeneration: t.controlGeneration,
            encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight, hostCertificateDERBase64: t.hostCertificateDERBase64,
            hostChallengeBase64: t.hostChallengeBase64, signingInputBase64: t.signingInputBase64,
            issuedAtUnixMilliseconds: t.issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: t.expiresAtUnixMilliseconds))
    try await harness.router.receive(WireCodec.encode(challenge))
    let received = try await requestTask.value
    #expect(received == challenge)
    let nativeAuthority = await harness.channel.nativeAttestationAuthority(for: challenge)
    #expect(nativeAuthority?.binding.primaryConnectionID == harness.session.connectionID)
    #expect(nativeAuthority?.sessionPublicKeyX963 == harness.host.sessionKey.publicKeyX963)
    #expect(nativeAuthority?.surface.surfaceID == descriptor.surfaceID)
    let proofTemplate = try nativePrimaryFixture("enroll-proof", as: InteractiveNativeVideoEnrollmentProofBodyV0.self)
    let proofTask = Task { try await harness.channel.submitNativeEnrollmentProof(for: challenge,
        signature: Data(base64Encoded: proofTemplate.body.signatureBase64)!, timeoutMilliseconds: 1000) }
    let proof = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentProofBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeEnrollProof))
    #expect(proof.body.challengeMessageID == challenge.messageID)
    let ready = try WireEnvelope(messageID: WireUUID(UUID()), correlationID: proof.messageID, sentAtUnixMilliseconds: 2_002,
        body: InteractiveNativeVideoReadyBodyV0(fence: proof.body.fence, challengeMessageID: challenge.messageID, portBase: 58989, streamContinuity: continuity ? true : nil))
    try await harness.router.receive(WireCodec.encode(ready))
    #expect(try await proofTask.value == ready)
    #expect(await harness.channel.currentNativeControlBinding() == nativeAuthority?.binding)
    let presentation = Task { try await harness.channel.acknowledgeNativePresentation(nativeGeneration: 1,
        encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight, timeoutMilliseconds: 1000) }
    let presentRequest = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoPresentationRequestBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativePresentRequest))
    #expect(presentRequest.body.fence == request.body.fence)
    #expect(presentRequest.body.challengeMessageID == challenge.messageID)
    let receiptTemplate = try nativePrimaryFixture("present-receipt", as: InteractiveNativeVideoPresentationReceiptBodyV0.self)
    let receipt = try WireEnvelope(messageID: WireUUID(UUID()), correlationID: presentRequest.messageID,
        sentAtUnixMilliseconds: 2_003, body: InteractiveNativeVideoPresentationReceiptBodyV0(fence: presentRequest.body.fence,
            challengeMessageID: challenge.messageID, nativeGeneration: 1,
            encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight,
            capturePixelWidth: receiptTemplate.body.capturePixelWidth, capturePixelHeight: receiptTemplate.body.capturePixelHeight,
            logicalWidthPoints: descriptor.logicalWidthPoints, logicalHeightPoints: descriptor.logicalHeightPoints))
    try await harness.router.receive(WireCodec.encode(receipt))
    #expect(try await presentation.value == receipt)
    if continuity {
        #expect(request.body.streamContinuity == true && request.body.previousFence == nil)
        #expect(await harness.channel.nativeStreamContinuityAvailable(ownedBy: ownerID))
        let retaining = Task { try await harness.channel.retainNativeEnrollment(ownedBy: ownerID) }
        let pause = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self,
            from: await nativePrimarySentFrame(harness, kind: .nativeCancel))
        #expect(pause.body.retainStream == true && pause.body.fence == request.body.fence)
        try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: pause.messageID,
            sentAtUnixMilliseconds: 2_004, body: try InteractiveNativeVideoCancelledBodyV0(fence: pause.body.fence, streamRetained: true))))
        try await retaining.value
        #expect(await harness.channel.nativeAttestationAuthority(for: challenge) == nil)
        #expect(await harness.channel.currentNativeControlBinding() == nativeAuthority?.binding)
        let stopping = Task { try await harness.channel.cancelNativeEnrollment(ownedBy: ownerID, timeoutMilliseconds: 1000) }
        let stop = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self,
            from: await nativePrimarySentFrame(harness, kind: .nativeCancel, excluding: pause.messageID))
        #expect(stop.body.retainStream == nil && stop.body.fence == pause.body.fence)
        try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: stop.messageID,
            sentAtUnixMilliseconds: 2_005, body: try InteractiveNativeVideoCancelledBodyV0(fence: stop.body.fence))))
        try await stopping.value
        #expect(await harness.router.state == .ready)
        return
    }
    do { _ = try await harness.channel.acknowledgeNativePresentation(nativeGeneration: 2,
        encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight); Issue.record("Replacement renderer admitted") } catch {}
    let mismatched = Task { try await harness.channel.acknowledgeNativePresentation(nativeGeneration: 1,
        encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight, timeoutMilliseconds: 1000) }
    let mismatchRequest = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoPresentationRequestBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativePresentRequest, excluding: presentRequest.messageID))
    let wrongGeometry = try WireEnvelope(messageID: WireUUID(UUID()), correlationID: mismatchRequest.messageID,
        sentAtUnixMilliseconds: 2_004, body: InteractiveNativeVideoPresentationReceiptBodyV0(fence: mismatchRequest.body.fence,
            challengeMessageID: challenge.messageID, nativeGeneration: 1,
            encodedWidth: descriptor.encodedWidth, encodedHeight: descriptor.encodedHeight,
            capturePixelWidth: receiptTemplate.body.capturePixelWidth, capturePixelHeight: receiptTemplate.body.capturePixelHeight,
            logicalWidthPoints: descriptor.logicalWidthPoints + 1, logicalHeightPoints: descriptor.logicalHeightPoints))
    try await harness.router.receive(WireCodec.encode(wrongGeometry))
    do { _ = try await mismatched.value; Issue.record("Wrong logical geometry receipt admitted") } catch {}
    let admitted = try #require(await harness.channel.nativeAttestationAuthority(for: challenge))
    #expect(admitted.binding.expiresAtMonotonicMilliseconds > UInt64(descriptor.expiresAtMonotonicMilliseconds))
    harness.clock.advance(to: UInt64(descriptor.expiresAtMonotonicMilliseconds) + 1)
    #expect(await harness.channel.nativeAttestationAuthority(for: challenge) == admitted)
    let cancelling = Task { try await harness.channel.cancelNativeEnrollment(timeoutMilliseconds: 1000) }
    let cancel = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeCancel))
    try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: cancel.messageID,
        sentAtUnixMilliseconds: 2_003, body: try InteractiveNativeVideoCancelledBodyV0(fence: cancel.body.fence))))
    try await cancelling.value
    #expect(await harness.channel.nativeAttestationAuthority(for: challenge) == nil)
    #expect(await harness.channel.currentNativeControlBinding() == admitted.binding,
        "Native cancellation cannot revive video, but the unchanged Control approval remains observable")
    #expect(await harness.router.state == .ready)

    let enrollingOwner = ClientNativeVideoEnrollmentSessionV0(channel: harness.channel, signer: NativeUnexpectedSigner(),
        validateCertificate: { _ in true }, monotonicMilliseconds: { 3000 })
    let enrolling = Task { try await enrollingOwner.enroll(descriptor: descriptor,
        clientCertificateDER: Data(base64Encoded: requestTemplate.body.clientCertificateDERBase64)!) }
    let secondRequest = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentRequestBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeEnrollRequest))
    #expect(secondRequest.body.fence.peerGeneration == request.body.fence.peerGeneration + 1)
    let stop = Task { await enrollingOwner.close() }
    let secondCancel = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelBodyV0>.self,
        from: await nativePrimarySentFrame(harness, kind: .nativeCancel))
    #expect(secondCancel.body.fence == secondRequest.body.fence)
    // Concurrent Stop joins this exact cancellation, including the channel's
    // own task-cancellation compensation; it must not replace the waiter.
    let joinedStop = Task { await enrollingOwner.close() }
    try await harness.router.receive(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: secondCancel.messageID,
        sentAtUnixMilliseconds: 2_004, body: try InteractiveNativeVideoCancelledBodyV0(fence: secondCancel.body.fence))))
    await stop.value
    await joinedStop.value
    do { _ = try await enrolling.value; Issue.record("Stopped enrollment completed") } catch {}
    #expect(await enrollingOwner.isCurrent() == false)
    #expect(await harness.router.state == .ready)
}

@Test(arguments: [(0, false), (0, true), (1, false), (1, true), (2, false), (2, true)], [0, 1, 2])
func interactivePrimaryChannelCompletesSelectedSessionApprovalFlow(delivery: (Int, Bool), acknowledgementDelivery: Int)
    async throws
{
    let (deliveryOrder, exceedsControlLifetime) = delivery
    let replyDuringAcknowledgementSend = acknowledgementDelivery != 0
    let harness = try await interactivePrimaryHarness()
    let effects: Set<InteractiveControlEffect> = [
        .view, .pointer, .keyboard,
    ]
    let submitted = try await harness.channel.beginSession(effects: effects)
    #expect(submitted == .requestSubmitted(effects: effects.sorted()))
    #expect(harness.events.events == [submitted])

    let requestFrame = try #require(await harness.transport.frames.first)
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSessionRequestBody>.self,
        from: requestFrame
    )
    try await harness.router.receive(WireCodec.encode(
        try interactivePrimaryChallenge(
            harness: harness,
            requestID: request.messageID,
            effects: effects
        )
    ))
    #expect(harness.events.events.count == 2)
    #expect(harness.events.events.last
        == .approvalSubmitted(effects: effects.sorted()))

    let proofFrame = try #require(await harness.transport.frames.last)
    let proof = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalProofBody>.self,
        from: proofFrame
    )
    try await harness.router.receive(WireCodec.encode(
        try interactivePrimaryAccepted(
            harness: harness,
            proofID: proof.messageID,
            lifetime: InteractiveSessionStateMachine.maximumDurationMilliseconds + (exceedsControlLifetime ? 1 : 0)
        )
    ))
    guard case let .accepted(session, acceptedEffects) =
            harness.events.events.last else {
        Issue.record("Expected accepted Control session")
        return
    }
    #expect(acceptedEffects == effects.sorted())
    #expect(session.primary.primaryConnectionID
        == harness.session.connectionID)
    #expect(await harness.channel.phase() == .accepted)
    #expect(await harness.router.state == .ready)

    try await harness.channel.beginInitialSurface()
    let initialRequestFrame = try #require(
        await harness.transport.frames.last
    )
    let initialRequest = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceRequestBodyV0>.self,
        from: initialRequestFrame
    )
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: session.interactiveSessionID,
        authorizationEpoch: session.authorizationEpoch,
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 10_000,
        expiresAtMonotonicMilliseconds: 20_000
    )
    let activationID = WireUUID(UUID())
    let descriptorWait = Task {
        try await harness.channel.waitForInitialDescriptor(
            timeoutMilliseconds: 1_000
        )
    }
    try await harness.router.receive(WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: initialRequest.messageID,
        sentAtUnixMilliseconds: 2_001,
        body: try InteractiveInitialSurfaceDescriptorBodyV0(
            activationID: activationID,
            descriptor: InteractiveSurfaceWireDescriptorV0(
                descriptor: descriptor,
                validForMilliseconds: 5_000
            ),
            sequence: 1
        )
    )))
    let admittedDescriptor = try await descriptorWait.value
    #expect(admittedDescriptor.surfaceID == descriptor.surfaceID)
    #expect(admittedDescriptor.interactiveSessionID
        == descriptor.interactiveSessionID)
    #expect(await harness.channel.initialSurfacePhase() == .awaitingMedia)

    let mediaFence = try await harness.channel.requestWebRTCOffer(
        for: admittedDescriptor
    )
    let offerRequestFrame = try #require(await harness.transport.frames.last)
    let offerRequest = try WireCodec.decode(
        WireEnvelope<InteractiveWebRTCOfferRequestBodyV0>.self,
        from: offerRequestFrame
    )
    #expect(offerRequest.body.fence == mediaFence)
    let mediaOffer = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: offerRequest.messageID,
        sentAtUnixMilliseconds: 2_002,
        body: try InteractiveWebRTCOfferBodyV0(
            fence: mediaFence,
            sdp: interactivePrimarySDP("11"),
            dtlsFingerprintHex: String(repeating: "11", count: 32)
        )
    )
    try await harness.router.receive(WireCodec.encode(mediaOffer))
    #expect(harness.events.events.last == .mediaOffer(mediaOffer))
    try await harness.channel.submitWebRTCAnswer(
        for: mediaOffer,
        sdp: interactivePrimarySDP("22"),
        dtlsFingerprintHex: String(repeating: "22", count: 32)
    )
    let mediaAnswerFrame = try #require(await harness.transport.frames.last)
    let mediaAnswer = try WireCodec.decode(
        WireEnvelope<InteractiveWebRTCAnswerBodyV0>.self,
        from: mediaAnswerFrame
    )
    #expect(mediaAnswer.body.offerMessageID == mediaOffer.messageID)
    let mediaReady = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: mediaAnswer.messageID,
        sentAtUnixMilliseconds: 2_003,
        body: try InteractiveWebRTCReadyBodyV0(
            fence: mediaFence, offerMessageID: mediaOffer.messageID
        )
    )
    try await harness.router.receive(WireCodec.encode(mediaReady))
    #expect(harness.events.events.last == .mediaReady(mediaReady))

    let configuration = try MediaRecordHeader(
        type: .decoderConfiguration,
        payloadLength: 16,
        interactiveSessionID: descriptor.interactiveSessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: descriptor.surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: 1,
        presentationTimeNanoseconds: 1_000,
        encodedWidth: descriptor.encodedWidth,
        encodedHeight: descriptor.encodedHeight
    )
    _ = try await harness.channel.admitInitialMedia(
        header: configuration,
        payloadByteCount: 16
    )
    let clean = try MediaRecordHeader(
        type: .videoAccessUnit,
        flags: [.cleanKeyframe],
        payloadLength: 128,
        interactiveSessionID: descriptor.interactiveSessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: descriptor.surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: 2,
        presentationTimeNanoseconds: 2_000,
        encodedWidth: descriptor.encodedWidth,
        encodedHeight: descriptor.encodedHeight
    )
    _ = try await harness.channel.admitInitialMedia(
        header: clean,
        payloadByteCount: 128
    )
    try await harness.channel.confirmInitialRenderedFrame(
        ClientDecodedFrameReceiptV0(
            generation: 1,
            fence: ClientDecoderFenceV0(header: clean),
            mediaSequence: clean.mediaSequence,
            presentationTimeNanoseconds:
                clean.presentationTimeNanoseconds,
            frameReference: UUID()
        )
    )
    if replyDuringAcknowledgementSend { await harness.transport.suspendNextSend() }
    let sendingAcknowledgement = Task { try await harness.channel.acknowledgeInitialSurface() }
    defer { Task { await harness.transport.resumeSend() } }
    if replyDuringAcknowledgementSend {
        let deadline = ContinuousClock.now + .seconds(2)
        while await harness.transport.sendIsSuspended == false, ContinuousClock.now < deadline { await Task.yield() }
        try #require(await harness.transport.sendIsSuspended)
        #expect(await harness.channel.initialSurfacePhase() == .awaitingAcknowledgement)
        if acknowledgementDelivery == 2 {
            await harness.router.invalidate()
            await harness.transport.resumeSend()
            await #expect(throws: ClientPrimaryCommandRouterErrorV0.invalidated) {
                try await sendingAcknowledgement.value
            }
            #expect(await harness.channel.initialSurfacePhase() == nil)
            #expect(await harness.channel.phase() == .closed)
            return
        }
    } else {
        try await sendingAcknowledgement.value
    }
    let acknowledgementFrame = try #require(
        await harness.transport.frames.last
    )
    let acknowledgement = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceAcknowledgementBodyV0>.self,
        from: acknowledgementFrame
    )
    #expect(acknowledgement.body.readyMediaSequence == 2)
    let deltaWhileAcknowledgementIsPending = try MediaRecordHeader(
        type: .videoAccessUnit,
        payloadLength: 128,
        interactiveSessionID: descriptor.interactiveSessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: descriptor.surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: 3,
        presentationTimeNanoseconds: 3_000,
        encodedWidth: descriptor.encodedWidth,
        encodedHeight: descriptor.encodedHeight
    )
    #expect(try await harness.channel.admitInitialMedia(
        header: deltaWhileAcknowledgementIsPending,
        payloadByteCount: 128
    ) == .videoAccessUnit(cleanKeyframe: false))
    try await harness.router.receive(WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: acknowledgement.messageID,
        sentAtUnixMilliseconds: 2_002,
        body: try InteractiveInitialSurfaceAcknowledgedBodyV0(
            acknowledgement: acknowledgement.body,
            inputResumed: true,
            sequence: 2
        )
    )))
    #expect(await harness.channel.initialSurfacePhase() == .active)
    if replyDuringAcknowledgementSend {
        await harness.transport.resumeSend()
        try await sendingAcknowledgement.value
        #expect(await harness.channel.initialSurfacePhase() == .active,
            "Completing a suspended send must not overwrite a committed acknowledgement reply")
    }
    if exceedsControlLifetime {
        let previousFrames = await harness.transport.frames.count
        let requestFixture = try nativePrimaryFixture("enroll-request", as: InteractiveNativeVideoEnrollmentRequestBodyV0.self)
        await #expect(throws: ClientInteractivePrimaryChannelErrorV0.unavailable) {
            try await harness.channel.requestNativeEnrollment(for: admittedDescriptor,
                clientCertificateDER: Data(base64Encoded: requestFixture.body.clientCertificateDERBase64)!)
        }
        #expect(await harness.transport.frames.count == previousFrames)
    } else {
        if deliveryOrder == 0 && acknowledgementDelivery == 0 {
            try await verifyRetiredNativeEnrollmentCannotCancelReplacement(harness, descriptor: admittedDescriptor)
        }
        if deliveryOrder == 0 && acknowledgementDelivery == 0 {
            try await verifyNativePrimaryRouting(harness, descriptor: admittedDescriptor, continuity: true)
        }
        try await verifyNativePrimaryRouting(harness, descriptor: admittedDescriptor)
    }

    let focusedRegionToken = WireUUID(UUID())
    let focus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 200,
            y: 120,
            width: 320,
            height: 80
        ),
        editable: true,
        secure: false
    )
    try await harness.router.receive(WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        channel: .events,
        sentAtUnixMilliseconds: 2_002,
        body: try InteractiveSurfaceFocusChangedBodyV0(
            interactiveSessionID: WireUUID(
                descriptor.interactiveSessionID
            ),
            authorizationEpoch: descriptor.authorizationEpoch,
            currentSurfaceID: WireUUID(descriptor.surfaceID),
            currentSurfaceRevision: descriptor.surfaceRevision,
            currentCoordinateSpaceRevision:
                descriptor.coordinateSpaceRevision,
            recommendedTargetKind: .focusedRegion,
            targetToken: focusedRegionToken,
            focus: InteractiveSurfaceWireFocusV0(focus),
            inputPaused: false,
            reason: .verifiedFocus,
            validForMilliseconds: 1_000,
            eventSequence: 1
        )
    )))
    let publishedFocus = try #require(harness.focusEvents.events.last)
    #expect(publishedFocus.targetToken == focusedRegionToken)
    #expect(publishedFocus.focus == focus)
    #expect(await harness.channel.latestFocusEvent() == publishedFocus)
    #expect(await harness.router.state == .ready)

    let steadyDelta = try MediaRecordHeader(
        type: .videoAccessUnit,
        payloadLength: 128,
        interactiveSessionID: descriptor.interactiveSessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: descriptor.surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: 4,
        presentationTimeNanoseconds: 4_000,
        encodedWidth: descriptor.encodedWidth,
        encodedHeight: descriptor.encodedHeight
    )
    #expect(try await harness.channel.admitInitialMedia(
        header: steadyDelta,
        payloadByteCount: 128
    ) == .videoAccessUnit(cleanKeyframe: false))
    if deliveryOrder != 0 {
        let oldMediaFence = try await harness.channel.requestWebRTCOffer(
            for: admittedDescriptor
        )
        let oldMediaRequestFrame = try #require(
            await harness.transport.frames.last
        )
        let oldMediaRequest = try WireCodec.decode(
            WireEnvelope<InteractiveWebRTCOfferRequestBodyV0>.self,
            from: oldMediaRequestFrame
        )
        let selection = try await harness.channel.prepareReplacementSurfaceSelection(
            targetKind: .desktop, targetToken: nil
        )
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
            from: selection.requestJSON
        )
        try await harness.channel.sendReplacementSurfaceSelection(selection.requestJSON)
        let replacement = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: descriptor.interactiveSessionID,
            authorizationEpoch: descriptor.authorizationEpoch,
            surfaceID: UUID(), kind: .desktop,
            surfaceRevision: .init(rawValue: 2),
            coordinateSpaceRevision: .init(rawValue: 2),
            encodedWidth: 1_280, encodedHeight: 720,
            logicalWidthPoints: 1_280, logicalHeightPoints: 720,
            interactionClasses: [.view, .pointer, .keyboard],
            privacyProfile: .visualOnly, metadataFields: [],
            createdAtMonotonicMilliseconds: 10_000,
            expiresAtMonotonicMilliseconds: 20_000
        )
        func mediaHeader(
            _ type: MediaRecordType, _ descriptor: AdaptiveSurfaceDescriptor,
            sequence: UInt64, clean: Bool = false
        ) throws -> MediaRecordHeader {
            try .init(
                type: type, flags: clean ? [.cleanKeyframe] : [],
                payloadLength: type == .discontinuity ? 0 : 128,
                interactiveSessionID: descriptor.interactiveSessionID,
                authorizationEpoch: descriptor.authorizationEpoch,
                surfaceID: descriptor.surfaceID,
                surfaceRevision: descriptor.surfaceRevision,
                coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
                mediaSequence: sequence, presentationTimeNanoseconds: sequence * 1_000,
                encodedWidth: type == .discontinuity ? 0 : descriptor.encodedWidth,
                encodedHeight: type == .discontinuity ? 0 : descriptor.encodedHeight
            )
        }
        let oldTail = try mediaHeader(.videoAccessUnit, descriptor, sequence: 5)
        let discontinuity = try mediaHeader(.discontinuity, replacement, sequence: 6)
        let selected = try WireCodec.encode(WireEnvelope(
            messageID: WireUUID(UUID()), correlationID: request.messageID,
            sentAtUnixMilliseconds: 2_003,
            body: try InteractiveSurfaceSelectedBodyV0(
                transitionID: WireUUID(UUID()),
                descriptor: InteractiveSurfaceWireDescriptorV0(
                    descriptor: replacement, validForMilliseconds: 5_000
                ),
                mediaSequenceBeforeTransition: 5, sequence: 3
            )
        ))
        if deliveryOrder == 1 {
            // Primary response overtakes the final old-source media record.
            let response = Task { try await harness.router.receive(selected) }
            try await Task.sleep(for: .milliseconds(20))
            #expect(await harness.channel.replacementSurfacePhase() == .awaitingSelection)
            _ = try await harness.channel.admitInitialMedia(header: oldTail, payloadByteCount: 128)
            try await response.value
            #expect(try await harness.channel.admitInitialMedia(
                header: discontinuity, payloadByteCount: 0
            ) == .discontinuity)
        } else {
            // Media socket reaches the replacement before the primary reply.
            _ = try await harness.channel.admitInitialMedia(header: oldTail, payloadByteCount: 128)
            let media = Task {
                try await harness.channel.admitInitialMedia(header: discontinuity, payloadByteCount: 0)
            }
            try await Task.sleep(for: .milliseconds(20))
            #expect(await harness.channel.replacementSurfacePhase() == .awaitingSelection)
            try await harness.router.receive(selected)
            #expect(try await media.value == .discontinuity)
        }
        #expect(await harness.channel.replacementSurfacePhase() == .awaitingMedia)
        let eventCountBeforeStaleOffer = harness.events.events.count
        try await harness.router.receive(WireCodec.encode(WireEnvelope(
            messageID: WireUUID(UUID()),
            correlationID: oldMediaRequest.messageID,
            sentAtUnixMilliseconds: 2_004,
            body: try InteractiveWebRTCOfferBodyV0(
                fence: oldMediaFence,
                sdp: interactivePrimarySDP("11"),
                dtlsFingerprintHex: String(repeating: "11", count: 32)
            )
        )))
        #expect(harness.events.events.count == eventCountBeforeStaleOffer)
        #expect(await harness.router.state == .ready)
        #expect(try await !harness.channel.confirmReplacementRenderedFrame(.init(
            generation: 1, fence: ClientDecoderFenceV0(header: oldTail),
            mediaSequence: 5, presentationTimeNanoseconds: 5_000, frameReference: UUID()
        )))
        _ = try await harness.channel.admitInitialMedia(
            header: mediaHeader(.decoderConfiguration, replacement, sequence: 7),
            payloadByteCount: 128
        )
        let replacementClean = try mediaHeader(.videoAccessUnit, replacement, sequence: 8, clean: true)
        _ = try await harness.channel.admitInitialMedia(header: replacementClean, payloadByteCount: 128)
        #expect(try await harness.channel.confirmReplacementRenderedFrame(.init(
            generation: 2, fence: ClientDecoderFenceV0(header: replacementClean),
            mediaSequence: 8, presentationTimeNanoseconds: 8_000, frameReference: UUID()
        )))
        let replyDuringReplacementSend = deliveryOrder == 1
            && !exceedsControlLifetime && acknowledgementDelivery == 0
        defer { Task { await harness.transport.resumeSend() } }
        if replyDuringReplacementSend { await harness.transport.suspendNextSend() }
        let sendingReplacementAck = Task {
            try await harness.channel.acknowledgeReplacementSurface()
        }
        if replyDuringReplacementSend {
            let deadline = ContinuousClock.now + .seconds(2)
            while await harness.transport.sendIsSuspended == false,
                  ContinuousClock.now < deadline { await Task.yield() }
            try #require(await harness.transport.sendIsSuspended)
        } else {
            try await sendingReplacementAck.value
        }
        let ackFrame = try #require(await harness.transport.frames.last)
        let ack = try WireCodec.decode(WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self, from: ackFrame)
        try await harness.router.receive(WireCodec.encode(WireEnvelope(
            messageID: WireUUID(UUID()), correlationID: ack.messageID,
            sentAtUnixMilliseconds: 2_004,
            body: try InteractiveSurfaceAcknowledgedBodyV0(
                acknowledgement: ack.body, inputResumed: true, sequence: 4
            )
        )))
        if replyDuringReplacementSend {
            await harness.transport.resumeSend()
            try await sendingReplacementAck.value
        }
        #expect(await harness.channel.replacementSurfacePhase() == .active)
        #expect(await harness.router.state == .ready)
        let sentBeforeInventory = await harness.transport.frames.count
        if replyDuringReplacementSend { await harness.transport.suspendNextSend() }
        let sendingInventory = Task {
            try await harness.channel.requestReplacementSurfaceTargets()
        }
        if replyDuringReplacementSend {
            let deadline = ContinuousClock.now + .seconds(2)
            while await harness.transport.sendIsSuspended == false,
                  ContinuousClock.now < deadline { await Task.yield() }
            try #require(await harness.transport.sendIsSuspended)
        } else {
            try await sendingInventory.value
        }
        let inventoryFrame = try #require(await harness.transport.frames.last)
        let inventoryRequest = try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceTargetsRequestBodyV0>.self,
            from: inventoryFrame
        )
        #expect(try WireCodec.messageKind(from: inventoryFrame) == .interactiveSurfaceTargetsRequest)
        #expect(await harness.transport.frames.count == sentBeforeInventory + 1,
            "An active surface inventory request sends only its own command")
        if replyDuringReplacementSend {
            // The live picker can overlap the view's display refresh. A reply
            // for one request must not be consumed by the other's pending ID.
            let requestingDisplays = Task {
                try await harness.channel.requestDisplayCatalog()
            }
            defer { requestingDisplays.cancel() }
            let displayDeadline = ContinuousClock.now + .seconds(2)
            while await harness.transport.frames.count < sentBeforeInventory + 2,
                  ContinuousClock.now < displayDeadline { await Task.yield() }
            let displayFrame = try #require(await harness.transport.frames.last)
            let displayRequest = try WireCodec.decode(
                WireEnvelope<InteractiveDisplayCatalogRequestBodyV1>.self,
                from: displayFrame
            )
            try await harness.router.receive(WireCodec.encode(WireEnvelope(
                messageID: WireUUID(UUID()),
                correlationID: inventoryRequest.messageID,
                sentAtUnixMilliseconds: 2_005,
                body: try InteractiveSurfaceTargetsResponseBodyV0(
                    interactiveSessionID: WireUUID(descriptor.interactiveSessionID),
                    authorizationEpoch: descriptor.authorizationEpoch,
                    inventoryRevision: 1,
                    validForMilliseconds: 100,
                    candidates: [],
                    sequence: 5
                )
            )))
            #expect(await harness.channel.replacementSurfaceTargets() == [])
            await harness.transport.resumeSend()
            try await sendingInventory.value
            #expect(await harness.channel.replacementSurfaceTargets() == [],
                "Completing a suspended send must not erase its already accepted inventory")
            let displayID = WireUUID(UUID())
            try await harness.router.receive(WireCodec.encode(WireEnvelope(
                messageID: WireUUID(UUID()),
                correlationID: displayRequest.messageID,
                sentAtUnixMilliseconds: 2_006,
                body: try InteractiveDisplayCatalogResponseBodyV1(
                    authorizationEpoch: descriptor.authorizationEpoch,
                    admissionRevision: 1,
                    selectedDisplayID: displayID,
                    validForMilliseconds: 1_000,
                    displays: [try InteractiveDisplayCandidateV1(
                        displayID: displayID, ordinal: 1,
                        pixelWidth: 1920, pixelHeight: 1080,
                        layoutX: 0, layoutY: 0,
                        layoutWidth: 1920, layoutHeight: 1080,
                        isMain: true
                    )]
                )
            )))
            #expect(try await requestingDisplays.value.selectedDisplayID == displayID)
            await harness.transport.suspendNextSend()
            let earlyDisplays = Task {
                try await harness.channel.requestDisplayCatalog(timeoutMilliseconds: 500)
            }
            defer {
                earlyDisplays.cancel()
                Task { await harness.transport.resumeSend() }
            }
            let earlyDeadline = ContinuousClock.now + .seconds(2)
            while await harness.transport.sendIsSuspended == false,
                  ContinuousClock.now < earlyDeadline { await Task.yield() }
            try #require(await harness.transport.sendIsSuspended)
            let earlyFrame = try #require(await harness.transport.frames.last)
            let earlyRequest = try WireCodec.decode(
                WireEnvelope<InteractiveDisplayCatalogRequestBodyV1>.self,
                from: earlyFrame
            )
            try await harness.router.receive(WireCodec.encode(WireEnvelope(
                messageID: WireUUID(UUID()),
                correlationID: earlyRequest.messageID,
                sentAtUnixMilliseconds: 2_007,
                body: try InteractiveDisplayCatalogResponseBodyV1(
                    authorizationEpoch: descriptor.authorizationEpoch,
                    admissionRevision: 2,
                    selectedDisplayID: displayID,
                    validForMilliseconds: 1_000,
                    displays: [try InteractiveDisplayCandidateV1(
                        displayID: displayID, ordinal: 1,
                        pixelWidth: 1920, pixelHeight: 1080,
                        layoutX: 0, layoutY: 0,
                        layoutWidth: 1920, layoutHeight: 1080,
                        isMain: true
                    )]
                )
            )))
            await harness.transport.resumeSend()
            #expect(try await earlyDisplays.value.selectedDisplayID == displayID,
                "An early authenticated catalog reply must resume its original waiter")
            #expect(await harness.router.state == .ready)
        }
        #expect(await harness.channel.replacementSurfacePhase() == .active)
        return
    }
    // A delayed product failure must not end a different accepted session,
    // enqueue a command, or fence that session's current input.
    let framesBeforeStaleRetirement = await harness.transport.frames.count
    await #expect(throws: ClientInteractivePrimaryChannelErrorV0.unavailable) {
        try await harness.channel.endSession(expectedInteractiveSessionID: UUID())
    }
    #expect(await harness.transport.frames.count == framesBeforeStaleRetirement)
    #expect(await harness.channel.phase() == .accepted)
    let inputFrame = try await harness.channel.makeInitialInputFrame(
        .pointerMove(x: 10, y: 20)
    )
    let input = try InteractiveInputCodec.decode(inputFrame)
    #expect(input.sequence == 1)
    #expect(input.surfaceID.rawValue == descriptor.surfaceID)
    if deliveryOrder == 0 {
        let resetFrame = try #require(await harness.channel.closeInitialInputFrame())
        let reset = try InteractiveInputCodec.decode(resetFrame)
        #expect(reset.sequence == 2)
        #expect(reset.input == .reset)
    }

    let stoppedFence = try await harness.channel.requestWebRTCOffer(
        for: admittedDescriptor
    )
    let stoppedOfferFrame = try #require(await harness.transport.frames.last)
    let stoppedOfferRequest = try WireCodec.decode(
        WireEnvelope<InteractiveWebRTCOfferRequestBodyV0>.self,
        from: stoppedOfferFrame
    )

    if deliveryOrder == 2 {
        await harness.transport.rejectNextSend()
        await #expect(throws: InteractivePrimaryTransportV0.Failure.injected) {
            try await harness.channel.endSession()
        }
        await #expect(throws: ClientInteractivePrimaryChannelErrorV0.unavailable) {
            try await harness.channel.makeInitialInputFrame(.pointerMove(x: 10, y: 20))
        }
    }
    let endSubmitted = try await harness.channel.endSession(
        expectedInteractiveSessionID: session.interactiveSessionID
    )
    await #expect(throws: ClientInteractivePrimaryChannelErrorV0.unavailable) {
        try await harness.channel.makeInitialInputFrame(.pointerMove(x: 10, y: 20))
    }
    #expect(endSubmitted == .endSubmitted(
        interactiveSessionID: session.interactiveSessionID,
        effects: effects.sorted()
    ))
    let endFrame = try #require(await harness.transport.frames.last)
    let framesAfterRetirement = await harness.transport.frames.count
    await #expect(throws: ClientInteractivePrimaryChannelErrorV0.unavailable) {
        try await harness.channel.endSession(
            expectedInteractiveSessionID: session.interactiveSessionID
        )
    }
    #expect(await harness.transport.frames.count == framesAfterRetirement)
    let end = try WireCodec.decode(
        WireEnvelope<InteractiveSessionEndBodyV0>.self,
        from: endFrame
    )
    #expect(end.body.interactiveSessionID.rawValue
        == session.interactiveSessionID)
    try await harness.router.receive(WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: stoppedOfferRequest.messageID,
        sentAtUnixMilliseconds: 2_003,
        body: try InteractiveWebRTCOfferBodyV0(
            fence: stoppedFence,
            sdp: interactivePrimarySDP("11"),
            dtlsFingerprintHex: String(repeating: "11", count: 32)
        )
    )))
    #expect(harness.events.events.last == endSubmitted)
    #expect(await harness.router.state == .ready)
    try await harness.router.receive(WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: end.messageID,
        sentAtUnixMilliseconds: 2_003,
        body: try InteractiveSessionEndedBodyV0(
            interactiveSessionID: end.body.interactiveSessionID,
            authorizationEpoch: end.body.authorizationEpoch,
            endedAtUnixMilliseconds: 2_003
        )
    )))
    #expect(harness.events.events.last == .ended(
        interactiveSessionID: session.interactiveSessionID,
        endedAtUnixMilliseconds: 2_003
    ))
    #expect(await harness.channel.phase() == .closed)
    #expect(await harness.channel.initialSurfacePhase() == nil)
    #expect(await harness.router.state == .ready)
}

@Test func concurrentFailedProductRetirementReservesOneEndRequest() async throws {
    let harness = try await interactivePrimaryHarness()
    _ = try await harness.channel.beginSession(effects: [.view])
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSessionRequestBody>.self,
        from: try #require(await harness.transport.frames.last)
    )
    try await harness.router.receive(WireCodec.encode(
        try interactivePrimaryChallenge(
            harness: harness, requestID: request.messageID, effects: [.view]
        )
    ))
    let proof = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalProofBody>.self,
        from: try #require(await harness.transport.frames.last)
    )
    try await harness.router.receive(WireCodec.encode(
        try interactivePrimaryAccepted(harness: harness, proofID: proof.messageID)
    ))
    guard case let .accepted(session, _) = harness.events.events.last else {
        Issue.record("Expected accepted session")
        return
    }
    let framesBefore = await harness.transport.frames.count
    let submittedCount = await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<8 {
            group.addTask {
                do {
                    _ = try await harness.channel.endSession(
                        expectedInteractiveSessionID: session.interactiveSessionID
                    )
                    return true
                } catch { return false }
            }
        }
        var count = 0
        for await submitted in group { if submitted { count += 1 } }
        return count
    }
    #expect(submittedCount == 1)
    #expect(await harness.transport.frames.count == framesBefore + 1)
    let end = try WireCodec.decode(
        WireEnvelope<InteractiveSessionEndBodyV0>.self,
        from: try #require(await harness.transport.frames.last)
    )
    #expect(end.body.interactiveSessionID.rawValue == session.interactiveSessionID)
    #expect(end.body.authorizationEpoch == session.authorizationEpoch)
    #expect(await harness.router.state == .ready)
}

@Test func interactivePrimaryRemoteDenialIsTypedWithoutKillingPrimary()
    async throws
{
    let harness = try await interactivePrimaryHarness()
    _ = try await harness.channel.beginSession(effects: [.view])
    let requestFrame = try #require(await harness.transport.frames.first)
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSessionRequestBody>.self,
        from: requestFrame
    )
    let rejection = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: request.messageID,
        sentAtUnixMilliseconds: 1_003,
        body: try ProtocolErrorResponseBody(
            code: "policy.denied",
            retry: .afterUserAction
        )
    )
    try await harness.router.receive(WireCodec.encode(rejection))

    #expect(harness.events.events.last == .remoteRejected(
        ClientInteractiveRemoteErrorV0(
            code: "policy.denied",
            retry: .afterUserAction
        )
    ))
    #expect(await harness.channel.phase() == .closed)
    #expect(await harness.router.state == .ready)
    let retry = try await harness.channel.beginSession(effects: [.view])
    #expect(retry == .requestSubmitted(effects: [.view]))
    #expect(await harness.channel.phase() == .awaitingApprovalChallenge)
    #expect(await harness.transport.frames.count == 2)
}

@Test func localApprovalFailureDoesNotKillPrimaryAndAllowsExplicitRetry()
    async throws
{
    let harness = try await interactivePrimaryHarness(
        signer: FailingInteractivePrimarySignerV0()
    )
    _ = try await harness.channel.beginSession(effects: [.view])
    let requestFrame = try #require(await harness.transport.frames.first)
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSessionRequestBody>.self,
        from: requestFrame
    )
    let challenge = try interactivePrimaryChallenge(
        harness: harness,
        requestID: request.messageID,
        effects: [.view]
    )

    try await harness.router.receive(WireCodec.encode(challenge))

    #expect(harness.events.events.last == .approvalFailed)
    #expect(await harness.channel.phase() == .closed)
    #expect(await harness.router.state == .ready)
    let retry = try await harness.channel.beginSession(effects: [.view])
    #expect(retry == .requestSubmitted(effects: [.view]))
    #expect(await harness.transport.frames.count == 2)
}

@Test func interactivePrimaryCustodiedSignerUsesOnlyControlPresenceReason()
    async throws
{
    let custody = InteractivePrimaryCustodyV0()
    let privateKey = P256.Signing.PrivateKey()
    let signer = try ClientCustodiedInteractiveApprovalSignerV0(
        custody: custody,
        approvalKey: ClientCustodiedPublicKeyV0(
            role: .approval,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: privateKey.publicKey.x963Representation,
            protection: .whenUnlockedThisDeviceOnlyUserPresence
        )
    )
    #expect(try await signer.signSessionChallenge(Data([0x01])).count == 64)
    #expect(await custody.approvalReasons == [.startInteractiveControl])
}

@Test func trustedInteractiveSignerUsesOnlyPairedSessionKeyWithoutPresence() async throws {
    let custody = InteractivePrimaryCustodyV0()
    let reference = try ClientSigningKeyReferenceV0(UUID())
    let key = try ClientCustodiedPublicKeyV0(
        role: .session, reference: reference,
        publicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation,
        protection: .afterFirstUnlockThisDeviceOnly
    )
    let signer = try ClientCustodiedTrustedInteractiveSignerV1(custody: custody, sessionKey: key)
    #expect(try await signer.signSessionChallenge(Data([1])) == Data(repeating: 0x55, count: 64))
    #expect(await custody.sessionReferences == [reference])
    #expect(await custody.approvalReasons.isEmpty)
}
