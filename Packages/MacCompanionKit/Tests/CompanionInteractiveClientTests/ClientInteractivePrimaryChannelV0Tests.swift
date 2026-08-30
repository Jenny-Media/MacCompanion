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

    func sendAuthenticatedCommand(_ frame: Data) async throws {
        frames.append(frame)
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
    func signAfterUserPresence(_ input: Data) async throws -> Data {
        Data(repeating: 0x66, count: 64)
    }
}

private enum InteractivePrimaryCustodyErrorV0: Error {
    case unsupported
}

private actor InteractivePrimaryCustodyV0: ClientIdentityKeyCustodyV0 {
    private(set) var approvalReasons: [ClientApprovalPresenceReasonV0] = []

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
        throw InteractivePrimaryCustodyErrorV0.unsupported
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

private struct InteractivePrimaryHarnessV0 {
    let host: ClientDurablePairedHostV0
    let session: ClientAuthenticatedSessionV0
    let transport: InteractivePrimaryTransportV0
    let router: ClientPrimaryCommandRouterV0
    let channel: ClientInteractivePrimaryChannelV0
    let events: InteractivePrimaryEventRecorderV0
    let focusEvents: InteractivePrimaryFocusRecorderV0
}

private func interactivePrimaryHarness() async throws
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
    let transport = InteractivePrimaryTransportV0()
    let router = try ClientPrimaryCommandRouterV0(
        authenticatedSession: session,
        transport: transport,
        monotonicNowNanoseconds: { 10_000_000_000 }
    )
    let events = InteractivePrimaryEventRecorderV0()
    let focusEvents = InteractivePrimaryFocusRecorderV0()
    let channel = try ClientInteractivePrimaryChannelV0(
        pairedHost: host,
        authenticatedSession: session,
        signer: InteractivePrimarySignerV0(),
        sender: router.sender(for: .control),
        environment: ClientInteractivePrimaryEnvironmentV0(
            makeMessageID: { WireUUID(UUID()) },
            wallNowUnixMilliseconds: { 1_002 },
            monotonicNowMilliseconds: { 10_000 }
        ),
        publish: { events.record($0) },
        publishFocus: { focusEvents.record($0) }
    )
    try await router.installReceiver(channel, for: .control)
    try await router.activate()
    return InteractivePrimaryHarnessV0(
        host: host,
        session: session,
        transport: transport,
        router: router,
        channel: channel,
        events: events,
        focusEvents: focusEvents
    )
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
    proofID: WireUUID
) throws -> WireEnvelope<InteractiveSessionAcceptedBody> {
    try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proofID,
        sentAtUnixMilliseconds: 2_000,
        body: try InteractiveSessionAcceptedBody(
            interactiveSessionID: WireUUID(UUID()),
            authorizationEpoch: harness.session.authorizationEpoch,
            expiresAtUnixMilliseconds: 100_000,
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

@Test(arguments: [0, 1, 2])
func interactivePrimaryChannelCompletesSelectedSessionApprovalFlow(deliveryOrder: Int)
    async throws
{
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
            proofID: proof.messageID
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
    try await harness.channel.acknowledgeInitialSurface()
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
        try await harness.channel.acknowledgeReplacementSurface()
        let ackFrame = try #require(await harness.transport.frames.last)
        let ack = try WireCodec.decode(WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self, from: ackFrame)
        try await harness.router.receive(WireCodec.encode(WireEnvelope(
            messageID: WireUUID(UUID()), correlationID: ack.messageID,
            sentAtUnixMilliseconds: 2_004,
            body: try InteractiveSurfaceAcknowledgedBodyV0(
                acknowledgement: ack.body, inputResumed: true, sequence: 4
            )
        )))
        #expect(await harness.channel.replacementSurfacePhase() == .active)
        #expect(await harness.router.state == .ready)
        return
    }
    let inputFrame = try await harness.channel.makeInitialInputFrame(
        .pointerMove(x: 10, y: 20)
    )
    let input = try InteractiveInputCodec.decode(inputFrame)
    #expect(input.sequence == 1)
    #expect(input.surfaceID.rawValue == descriptor.surfaceID)
    let resetFrame = try #require(
        await harness.channel.closeInitialInputFrame()
    )
    let reset = try InteractiveInputCodec.decode(resetFrame)
    #expect(reset.sequence == 2)
    #expect(reset.input == .reset)

    let endSubmitted = try await harness.channel.endSession()
    #expect(endSubmitted == .endSubmitted(
        interactiveSessionID: session.interactiveSessionID,
        effects: effects.sorted()
    ))
    let endFrame = try #require(await harness.transport.frames.last)
    let end = try WireCodec.decode(
        WireEnvelope<InteractiveSessionEndBodyV0>.self,
        from: endFrame
    )
    #expect(end.body.interactiveSessionID.rawValue
        == session.interactiveSessionID)
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
    #expect(try await signer.signAfterUserPresence(Data([0x01])).count == 64)
    #expect(await custody.approvalReasons == [.startInteractiveControl])
}
