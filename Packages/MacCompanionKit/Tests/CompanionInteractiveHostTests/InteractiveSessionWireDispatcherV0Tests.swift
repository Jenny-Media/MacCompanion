import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionPersistence
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let dispatcherHostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
private let dispatcherDeviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
private let dispatcherClientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let dispatcherDisplayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000001")!
private let dispatcherSecondDisplayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000002")!
private let dispatcherApprovalID = UUID(uuidString: "018f6600-0000-7000-8000-000000000001")!
private let dispatcherSessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let dispatcherInputChannelID = UUID(uuidString: "018f6800-0000-7000-8000-000000000001")!
private let dispatcherMediaChannelID = UUID(uuidString: "018f6800-0000-7000-8000-000000000002")!
private let dispatcherFingerprint = Data((0x80..<0xa0).map(UInt8.init))
private let dispatcherConnectionID = Data((0x00..<0x10).map(UInt8.init))
private let dispatcherServerChallenge = Data((0x30..<0x50).map(UInt8.init))
private let dispatcherInputCredential = Data((0x40..<0x60).map(UInt8.init))
private let dispatcherMediaCredential = Data((0x60..<0x80).map(UInt8.init))

private enum DispatcherTestError: Error { case installFailed }

private struct DispatcherAuditClock: InteractiveAuditWallClockV0 {
    let value: Int64
    func nowUnixMilliseconds() -> Int64 { value }
}

private func dispatcherApprovalKey() throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 2
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}

private func dispatcherContext(
    hostState: HostState = .userSessionActive,
    grantRevision: UInt64 = 5,
    monotonicNow: UInt64 = 1_000,
    wallNow: Int64 = 1_724_000_000_000
) throws -> InteractiveSessionCommandContextV0 {
    try InteractiveSessionCommandContextV0(
        deviceID: dispatcherDeviceID,
        clientID: dispatcherClientID,
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: grantRevision),
        policyRevision: .init(rawValue: 6),
        primaryConnectionID: dispatcherConnectionID,
        hostID: dispatcherHostID,
        hostFingerprint: dispatcherFingerprint,
        hostState: hostState,
        wallNowUnixMilliseconds: wallNow,
        monotonicNowMilliseconds: monotonicNow
    )
}

private func dispatcherSnapshot(
    grants: [String] = [InteractiveControlCapabilityV0.identifier],
    visible: Bool = true,
    displayID: UUID? = dispatcherDisplayID,
    grantRevision: UInt64 = 5,
    visibleRevision: UInt64 = 1
) throws -> InteractiveSessionAdmissionSnapshotV0 {
    try InteractiveSessionAdmissionSnapshotV0(
        deviceID: dispatcherDeviceID,
        clientID: dispatcherClientID,
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: grantRevision),
        policyRevision: .init(rawValue: 6),
        approvalPublicKeyX963: try dispatcherApprovalKey().publicKey.x963Representation,
        grants: CapabilityGrantSet(grants),
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        visibleMenuAppAvailable: visible,
        visibleMenuAppGeneration: UUID(
            uuidString: "019b7300-0000-7000-8000-000000000001"
        )!,
        visibleMenuAppRevision: visibleRevision,
        selectedDisplayID: displayID
    )
}

private actor DispatcherDisplaySelection:
    InteractiveDisplaySelectionDispatchingV1
{
    private(set) var catalogCount = 0
    private(set) var selectedIDs: [UUID] = []

    func displayCatalog(
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplayCatalogResponseBodyV1 {
        catalogCount += 1
        return try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            admissionRevision: 1,
            selectedDisplayID: WireUUID(dispatcherDisplayID),
            validForMilliseconds: 10_000,
            displays: [
                try .init(
                    displayID: WireUUID(dispatcherDisplayID),
                    ordinal: 1,
                    pixelWidth: 3_024,
                    pixelHeight: 1_964,
                    isMain: true
                ),
                try .init(
                    displayID: WireUUID(dispatcherSecondDisplayID),
                    ordinal: 2,
                    pixelWidth: 2_560,
                    pixelHeight: 1_440,
                    isMain: false
                ),
            ]
        )
    }

    func selectDisplay(
        _ request: InteractiveDisplaySelectBodyV1,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplaySelectedBodyV1 {
        selectedIDs.append(request.displayID.rawValue)
        return try InteractiveDisplaySelectedBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            admissionRevision: request.expectedAdmissionRevision + 1,
            selectedDisplayID: request.displayID
        )
    }
}

private actor DispatcherAdmission: InteractiveSessionAdmissionReadingV0 {
    private var values: [InteractiveSessionAdmissionSnapshotV0?]
    private(set) var readCount = 0

    init(_ values: [InteractiveSessionAdmissionSnapshotV0?]) {
        self.values = values
    }

    func snapshot(deviceID: UUID) async throws
        -> InteractiveSessionAdmissionSnapshotV0? {
        readCount += 1
        guard !values.isEmpty else { return nil }
        return values.count == 1 ? values[0] : values.removeFirst()
    }
}

private actor DispatcherMaterials: InteractiveSessionMaterialGeneratingV0 {
    private(set) var approvalCount = 0
    private(set) var bootstrapCount = 0

    func approvalMaterials() async throws -> InteractiveApprovalMaterialsV0 {
        approvalCount += 1
        return try InteractiveApprovalMaterialsV0(
            approvalID: dispatcherApprovalID,
            serverChallenge: dispatcherServerChallenge
        )
    }

    func bootstrapMaterials() async throws -> InteractiveSessionBootstrapMaterials {
        bootstrapCount += 1
        return InteractiveSessionBootstrapMaterials(
            interactiveSessionID: dispatcherSessionID,
            inputChannelID: dispatcherInputChannelID,
            inputCredential: dispatcherInputCredential,
            mediaChannelID: dispatcherMediaChannelID,
            mediaCredential: dispatcherMediaCredential
        )
    }
}

private actor DispatcherRuntime: InteractiveSessionRuntimeOwningV0 {
    struct Termination: Equatable, Sendable {
        let sessionID: UUID
        let connectionID: Data
        let reason: InteractiveSessionEndReason
    }

    private let failInstall: Bool
    private(set) var installed: [InteractiveSessionBootstrap] = []
    private(set) var terminations: [Termination] = []

    init(failInstall: Bool = false) {
        self.failInstall = failInstall
    }

    func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        if failInstall { throw DispatcherTestError.installFailed }
        installed.append(bootstrap)
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        terminations.append(Termination(
            sessionID: interactiveSessionID,
            connectionID: primaryConnectionID,
            reason: reason
        ))
    }
}

private actor DispatcherSurfaceControl:
    InteractiveSurfaceControlDispatchingV0
{
    private let onClosed: @Sendable () async -> Void
    init(onClosed: @escaping @Sendable () async -> Void = {}) {
        self.onClosed = onClosed
    }
    private(set) var initialRequests:
        [InteractiveInitialSurfaceRequestBodyV0] = []
    private(set) var initialAcknowledgements:
        [InteractiveInitialSurfaceAcknowledgementBodyV0] = []
    private(set) var targetRequests:
        [InteractiveSurfaceTargetsRequestBodyV0] = []
    private(set) var selections: [InteractiveSurfaceSelectBodyV0] = []
    private(set) var acknowledgements:
        [InteractiveSurfaceAcknowledgementBodyV0] = []
    private(set) var closeCount = 0
    let transitionID = WireUUID(UUID())
    let activationID = WireUUID(UUID())
    let surfaceID = UUID()

    func requestInitial(
        _ request: InteractiveInitialSurfaceRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceDescriptorBodyV0 {
        initialRequests.append(request)
        let descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: dispatcherSessionID,
            authorizationEpoch: .init(rawValue: 4),
            surfaceID: surfaceID,
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
            createdAtMonotonicMilliseconds: 1_000,
            expiresAtMonotonicMilliseconds: 11_000
        )
        return try InteractiveInitialSurfaceDescriptorBodyV0(
            activationID: activationID,
            descriptor: InteractiveSurfaceWireDescriptorV0(
                descriptor: descriptor,
                validForMilliseconds: 10_000
            ),
            sequence: 1
        )
    }

    func acknowledgeInitial(
        _ request: InteractiveInitialSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceAcknowledgedBodyV0 {
        initialAcknowledgements.append(request)
        return try InteractiveInitialSurfaceAcknowledgedBodyV0(
            acknowledgement: request,
            inputResumed: true,
            sequence: 2
        )
    }

    func targets(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceTargetsResponseBodyV0 {
        targetRequests.append(request)
        return try InteractiveSurfaceTargetsResponseBodyV0(
            interactiveSessionID: request.interactiveSessionID,
            authorizationEpoch: request.authorizationEpoch,
            inventoryRevision: 1,
            validForMilliseconds: 10_000,
            candidates: [],
            sequence: 3
        )
    }

    func select(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceSelectedBodyV0 {
        selections.append(request)
        let descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: dispatcherSessionID,
            authorizationEpoch: .init(rawValue: 4),
            surfaceID: surfaceID,
            kind: .desktop,
            surfaceRevision: .init(rawValue: 2),
            coordinateSpaceRevision: .init(rawValue: 2),
            encodedWidth: 1_280,
            encodedHeight: 720,
            logicalWidthPoints: 1_280,
            logicalHeightPoints: 720,
            interactionClasses: [.view, .pointer, .keyboard],
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: 1_000,
            expiresAtMonotonicMilliseconds: 11_000
        )
        return try InteractiveSurfaceSelectedBodyV0(
            transitionID: transitionID,
            descriptor: InteractiveSurfaceWireDescriptorV0(
                descriptor: descriptor,
                validForMilliseconds: 10_000
            ),
            mediaSequenceBeforeTransition: 4,
            sequence: 4
        )
    }

    func acknowledge(
        _ request: InteractiveSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceAcknowledgedBodyV0 {
        acknowledgements.append(request)
        return try InteractiveSurfaceAcknowledgedBodyV0(
            acknowledgement: request,
            inputResumed: true,
            sequence: 5
        )
    }

    func primarySessionClosed() async {
        await onClosed()
        closeCount += 1
    }
}

private actor SuspendingDispatcherAdmission: InteractiveSessionAdmissionReadingV0 {
    private let value: InteractiveSessionAdmissionSnapshotV0
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ value: InteractiveSessionAdmissionSnapshotV0) {
        self.value = value
    }

    func snapshot(deviceID: UUID) async throws
        -> InteractiveSessionAdmissionSnapshotV0? {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return value
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendingDispatcherRuntime: InteractiveSessionRuntimeOwningV0 {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var liveSessionIDs = Set<UUID>()
    private(set) var logicalTerminationCount = 0

    func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        liveSessionIDs.insert(bootstrap.acceptedBody.interactiveSessionID.rawValue)
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        if liveSessionIDs.remove(interactiveSessionID) != nil {
            logicalTerminationCount += 1
        }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct PendingDispatcherFlow {
    let dispatcher: InteractiveSessionWireDispatcherV0
    let admission: DispatcherAdmission
    let materials: DispatcherMaterials
    let runtime: DispatcherRuntime
    let request: WireEnvelope<InteractiveSessionRequestBody>
    let challenge: WireEnvelope<InteractiveApprovalChallengeBody>
}

private func pendingDispatcherFlow(
    snapshots: [InteractiveSessionAdmissionSnapshotV0?]? = nil,
    runtime: DispatcherRuntime = DispatcherRuntime(),
    surfaceControl:
        (any InteractiveSurfaceControlDispatchingV0)? = nil,
    auditWriter: (any InteractiveAuditWritingV0)? = nil,
    auditWallClock: any InteractiveAuditWallClockV0 =
        SystemInteractiveAuditWallClockV0()
) async throws -> PendingDispatcherFlow {
    let admission = DispatcherAdmission(
        try snapshots ?? [dispatcherSnapshot()]
    )
    let materials = DispatcherMaterials()
    let dispatcher = InteractiveSessionWireDispatcherV0(
        admission: admission,
        materials: materials,
        runtime: runtime,
        surfaceControl: surfaceControl,
        auditWriter: auditWriter,
        auditWallClock: auditWallClock
    )
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_000,
        body: try InteractiveSessionRequestBody(
            effects: [.view, .pointer, .keyboard, .text]
        )
    )
    let challengeID = WireUUID(UUID())
    let responseData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(request),
        context: dispatcherContext(),
        responseMessageID: challengeID
    )
    let challenge = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalChallengeBody>.self,
        from: responseData
    )
    return PendingDispatcherFlow(
        dispatcher: dispatcher,
        admission: admission,
        materials: materials,
        runtime: runtime,
        request: request,
        challenge: challenge
    )
}

@Test func dispatcherRoutesInitialAndReplacementSurfaceOnlyInsideActiveSession()
    async throws
{
    let surfaceControl = DispatcherSurfaceControl()
    let flow = try await pendingDispatcherFlow(
        surfaceControl: surfaceControl
    )
    let proof = try dispatcherProof(for: flow.challenge)
    _ = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )

    let initialRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_011,
        body: try InteractiveInitialSurfaceRequestBodyV0(
            interactiveSessionID: WireUUID(dispatcherSessionID),
            authorizationEpoch: .init(rawValue: 4),
            sequence: 1
        )
    )
    let initialData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(initialRequest),
        context: dispatcherContext(monotonicNow: 1_011),
        responseMessageID: WireUUID(UUID())
    )
    let initial = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceDescriptorBodyV0>.self,
        from: initialData
    )
    #expect(initial.correlationID == initialRequest.messageID)
    #expect(initial.body.sequence == 1)
    #expect(await surfaceControl.initialRequests == [initialRequest.body])

    let initialAck = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_012,
        body: try InteractiveInitialSurfaceAcknowledgementBodyV0(
            interactiveSessionID: initial.body.descriptor.interactiveSessionID,
            authorizationEpoch: initial.body.descriptor.authorizationEpoch,
            activationID: initial.body.activationID,
            surfaceID: initial.body.descriptor.surfaceID,
            surfaceRevision: initial.body.descriptor.surfaceRevision,
            coordinateSpaceRevision:
                initial.body.descriptor.coordinateSpaceRevision,
            readyMediaSequence: 2,
            sequence: 2
        )
    )
    let initialAckData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(initialAck),
        context: dispatcherContext(monotonicNow: 1_012),
        responseMessageID: WireUUID(UUID())
    )
    let initialAcknowledged = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceAcknowledgedBodyV0>.self,
        from: initialAckData
    )
    #expect(initialAcknowledged.correlationID == initialAck.messageID)
    #expect(initialAcknowledged.body.sequence == 2)
    #expect(await surfaceControl.initialAcknowledgements == [initialAck.body])

    let targetsRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_013,
        body: try InteractiveSurfaceTargetsRequestBodyV0(
            interactiveSessionID: WireUUID(dispatcherSessionID),
            authorizationEpoch: .init(rawValue: 4),
            sequence: 3
        )
    )
    let targetsData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(targetsRequest),
        context: dispatcherContext(monotonicNow: 1_013),
        responseMessageID: WireUUID(UUID())
    )
    let targets = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
        from: targetsData
    )
    #expect(targets.correlationID == targetsRequest.messageID)
    #expect(targets.body.sequence == 3)
    #expect(await surfaceControl.targetRequests == [targetsRequest.body])

    let selection = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_020,
        body: try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: WireUUID(dispatcherSessionID),
            authorizationEpoch: .init(rawValue: 4),
            currentSurfaceID: WireUUID(UUID()),
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            targetKind: .desktop,
            targetToken: nil,
            sequence: 4
        )
    )
    let selectedData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(selection),
        context: dispatcherContext(monotonicNow: 1_020),
        responseMessageID: WireUUID(UUID())
    )
    let selected = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceSelectedBodyV0>.self,
        from: selectedData
    )
    #expect(selected.correlationID == selection.messageID)
    #expect(selected.body.sequence == 4)
    #expect(await surfaceControl.selections == [selection.body])

    let acknowledgement = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_030,
        body: try InteractiveSurfaceAcknowledgementBodyV0(
            interactiveSessionID: selected.body.descriptor.interactiveSessionID,
            authorizationEpoch: selected.body.descriptor.authorizationEpoch,
            transitionID: selected.body.transitionID,
            surfaceID: selected.body.descriptor.surfaceID,
            surfaceRevision: selected.body.descriptor.surfaceRevision,
            coordinateSpaceRevision:
                selected.body.descriptor.coordinateSpaceRevision,
            readyMediaSequence: 9,
            sequence: 5
        )
    )
    let acknowledgedData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(acknowledgement),
        context: dispatcherContext(monotonicNow: 1_030),
        responseMessageID: WireUUID(UUID())
    )
    let acknowledged = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceAcknowledgedBodyV0>.self,
        from: acknowledgedData
    )
    #expect(acknowledged.correlationID == acknowledgement.messageID)
    #expect(acknowledged.body.sequence == 5)
    #expect(acknowledged.body.inputResumed)
    #expect(await surfaceControl.acknowledgements == [
        acknowledgement.body,
    ])

    await flow.dispatcher.primarySessionClosed()
    await flow.dispatcher.primarySessionClosed()
    #expect(await surfaceControl.closeCount == 1)
}

private func dispatcherProof(
    for challenge: WireEnvelope<InteractiveApprovalChallengeBody>
) throws -> WireEnvelope<InteractiveApprovalProofBody> {
    let signature = try dispatcherApprovalKey().signature(
        for: challenge.body.signingInput(version: challenge.version)
    ).rawRepresentation
    return try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: challenge.messageID,
        sentAtUnixMilliseconds: 1_724_000_000_010,
        body: InteractiveApprovalProofBody(
            approvalID: challenge.body.approvalID,
            signature: WireBytes64(signature)
        )
    )
}

@Test func dispatcherSelectsSecondDisplayBeforeBindingNextSession()
    async throws
{
    let before = try dispatcherSnapshot()
    let after = try dispatcherSnapshot(
        displayID: dispatcherSecondDisplayID,
        visibleRevision: 2
    )
    let admission = DispatcherAdmission([before, before, after, after])
    let displays = DispatcherDisplaySelection()
    let dispatcher = InteractiveSessionWireDispatcherV0(
        admission: admission,
        materials: DispatcherMaterials(),
        runtime: DispatcherRuntime(),
        displaySelection: displays
    )
    let context = try dispatcherContext()

    let catalogRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
        body: try InteractiveDisplayCatalogRequestBodyV1(
            authorizationEpoch: context.authorizationEpoch
        )
    )
    let catalogData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(catalogRequest),
        context: context,
        responseMessageID: WireUUID(UUID())
    )
    let catalog = try WireCodec.decode(
        WireEnvelope<InteractiveDisplayCatalogResponseBodyV1>.self,
        from: catalogData
    )
    #expect(catalog.correlationID == catalogRequest.messageID)
    #expect(catalog.body.displays.count == 2)
    #expect(catalog.body.selectedDisplayID.rawValue == dispatcherDisplayID)

    let selectRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: context.wallNowUnixMilliseconds + 1,
        body: try InteractiveDisplaySelectBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            expectedAdmissionRevision: catalog.body.admissionRevision,
            displayID: WireUUID(dispatcherSecondDisplayID)
        )
    )
    let selectedData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(selectRequest),
        context: try dispatcherContext(wallNow: context.wallNowUnixMilliseconds + 1),
        responseMessageID: WireUUID(UUID())
    )
    let selected = try WireCodec.decode(
        WireEnvelope<InteractiveDisplaySelectedBodyV1>.self,
        from: selectedData
    )
    #expect(selected.correlationID == selectRequest.messageID)
    #expect(selected.body.admissionRevision == 2)
    #expect(selected.body.selectedDisplayID.rawValue == dispatcherSecondDisplayID)
    #expect(await displays.selectedIDs == [dispatcherSecondDisplayID])

    let sessionRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: context.wallNowUnixMilliseconds + 2,
        body: try InteractiveSessionRequestBody(effects: [.view])
    )
    let challengeData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(sessionRequest),
        context: try dispatcherContext(wallNow: context.wallNowUnixMilliseconds + 2),
        responseMessageID: WireUUID(UUID())
    )
    let challenge = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalChallengeBody>.self,
        from: challengeData
    )
    #expect(challenge.body.selectedDisplayID.rawValue == dispatcherSecondDisplayID)
}

@Test func dispatcherCreatesChallengeAndInstallsBootstrapBeforeAcceptance() async throws {
    let flow = try await pendingDispatcherFlow()
    #expect(flow.challenge.correlationID == flow.request.messageID)
    #expect(flow.challenge.body.hostID == WireUUID(dispatcherHostID))
    #expect(flow.challenge.body.clientID == WireUUID(dispatcherClientID))
    #expect(flow.challenge.body.primaryConnectionID.rawValue == dispatcherConnectionID)
    #expect(flow.challenge.body.selectedDisplayID == WireUUID(dispatcherDisplayID))
    #expect(flow.challenge.body.effects == [.keyboard, .pointer, .text, .view])
    #expect(flow.challenge.body.expiresAtUnixMilliseconds
        - flow.challenge.body.issuedAtUnixMilliseconds == 60_000)

    let proof = try dispatcherProof(for: flow.challenge)
    let acceptedData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010, wallNow: 1_724_000_000_010),
        responseMessageID: WireUUID(UUID())
    )
    let accepted = try WireCodec.decode(
        WireEnvelope<InteractiveSessionAcceptedBody>.self,
        from: acceptedData
    )
    #expect(accepted.correlationID == proof.messageID)
    #expect(accepted.body.interactiveSessionID == WireUUID(dispatcherSessionID))
    #expect(accepted.body.inputChannel.role == .input)
    #expect(accepted.body.mediaChannel.role == .media)
    #expect(await flow.runtime.installed.count == 1)
    #expect(await flow.runtime.installed[0].session.state == .starting)
    #expect(await flow.dispatcher.activeInteractiveSessionID == dispatcherSessionID)
    #expect(await !flow.dispatcher.hasPendingApproval)
}

@Test func dispatcherRejectsSecondSessionWithoutReplacingActiveOwner() async throws {
    let flow = try await pendingDispatcherFlow()
    let proof = try dispatcherProof(for: flow.challenge)
    _ = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )

    let secondRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_020,
        body: try InteractiveSessionRequestBody(effects: [.view])
    )
    let rejectedData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(secondRequest),
        context: dispatcherContext(
            monotonicNow: 1_020,
            wallNow: 1_724_000_000_020
        ),
        responseMessageID: WireUUID(UUID())
    )
    let rejected = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: rejectedData
    )
    #expect(rejected.body.code == "interactive.sessionActive")
    #expect(rejected.body.retry == .afterUserAction)
    #expect(await flow.dispatcher.activeInteractiveSessionID
        == dispatcherSessionID)
    #expect(await flow.runtime.terminations.isEmpty)
}

@Test func remoteEndClearsAdmissionBeforeCompleteSafetyTeardown()
    async throws
{
    let runtime = DispatcherRuntime()
    let surfaceControl = DispatcherSurfaceControl(onClosed: {
        #expect(await runtime.terminations.count == 1)
    })
    let flow = try await pendingDispatcherFlow(
        runtime: runtime,
        surfaceControl: surfaceControl
    )
    let proof = try dispatcherProof(for: flow.challenge)
    _ = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    let end = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_020,
        body: try InteractiveSessionEndBodyV0(
            interactiveSessionID: WireUUID(dispatcherSessionID),
            authorizationEpoch: .init(rawValue: 4)
        )
    )
    let endedData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(end),
        context: dispatcherContext(
            monotonicNow: 1_020,
            wallNow: 1_724_000_000_020
        ),
        responseMessageID: WireUUID(UUID())
    )
    let ended = try WireCodec.decode(
        WireEnvelope<InteractiveSessionEndedBodyV0>.self,
        from: endedData
    )

    #expect(ended.correlationID == end.messageID)
    #expect(ended.body.interactiveSessionID == WireUUID(dispatcherSessionID))
    #expect(ended.body.authorizationEpoch == .init(rawValue: 4))
    #expect(ended.body.endedAtUnixMilliseconds == 1_724_000_000_020)
    #expect(await flow.dispatcher.activeInteractiveSessionID == nil)
    #expect(await surfaceControl.closeCount == 1)
    #expect(await flow.runtime.terminations == [
        .init(
            sessionID: dispatcherSessionID,
            connectionID: dispatcherConnectionID,
            reason: .clientRequested
        ),
    ])

    await #expect(throws:
        InteractiveSessionWireDispatcherErrorV0.admissionChanged
    ) {
        _ = try await flow.dispatcher.dispatch(
            requestJSON: WireCodec.encode(end),
            context: dispatcherContext(
                monotonicNow: 1_021,
                wallNow: 1_724_000_000_021
            ),
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await flow.runtime.terminations.count == 1)
}

@Test func interactiveAuditApprovalCommitsBeforeRuntimeAndPublishesStarted() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-interactive-audit-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path
    )
    let auditWriter = BoundedInteractiveAuditWriterV0(store: auditStore)
    let flow = try await pendingDispatcherFlow(
        auditWriter: auditWriter,
        auditWallClock: DispatcherAuditClock(value: 1_724_000_000_020)
    )
    let proof = try dispatcherProof(for: flow.challenge)

    _ = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(
            monotonicNow: 1_010,
            wallNow: 1_724_000_000_010
        ),
        responseMessageID: WireUUID(UUID())
    )

    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [
        .interactiveStarted,
        .interactiveApproved,
        .interactiveRequested,
    ])
    #expect(page.events.map(\.draft.importance) == [
        .bestEffort,
        .requiredBeforeEffect,
        .bestEffort,
    ])
    #expect(page.events.allSatisfy {
        $0.draft.subjectDeviceID == dispatcherDeviceID
            && $0.draft.capabilityID == InteractiveControlCapabilityV0.identifier
    })
    #expect(await flow.runtime.installed.count == 1)
    #expect(await auditWriter.health() == .healthy)

    await flow.dispatcher.primarySessionClosed()
    let afterDisconnect = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(afterDisconnect.events.first?.draft.code == .interactiveStopped)
    #expect(afterDisconnect.events.first?.draft.outcome == .cancelled)
    #expect(afterDisconnect.events.first?.draft.observedAtUnixMilliseconds
        == 1_724_000_000_020)
}

@Test func requiredInteractiveAuditFailurePreventsRuntimeInstall() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-interactive-audit-fault-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: [.afterCompaction]
    )
    let auditWriter = BoundedInteractiveAuditWriterV0(store: auditStore)
    let flow = try await pendingDispatcherFlow(auditWriter: auditWriter)
    let proof = try dispatcherProof(for: flow.challenge)

    let responseData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(
            monotonicNow: 1_010,
            wallNow: 1_724_000_000_010
        ),
        responseMessageID: WireUUID(UUID())
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: responseData
    )

    #expect(error.body.code == "storage.securityUnavailable")
    #expect(error.body.safeArguments == .object([
        .init(key: "recovery", value: .string("localRepair")),
    ]))
    #expect(await flow.runtime.installed.isEmpty)
    #expect(await flow.dispatcher.activeInteractiveSessionID == nil)
    #expect(await auditWriter.health() == .degraded)
}

@Test func droppedStartedAuditDegradesHealthWithoutUndoingInstalledRuntime() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-interactive-audit-drop-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        configuration: try AuditStoreConfigurationV0(
            logicalByteLimit: 16 * 1_024 * 1_024,
            retainedRowLimit: 50_000,
            retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
            rateLimitAttempts: 2,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    let auditWriter = BoundedInteractiveAuditWriterV0(store: auditStore)
    let flow = try await pendingDispatcherFlow(auditWriter: auditWriter)
    let proof = try dispatcherProof(for: flow.challenge)

    _ = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(
            monotonicNow: 1_010,
            wallNow: 1_724_000_000_010
        ),
        responseMessageID: WireUUID(UUID())
    )

    #expect(await flow.runtime.installed.count == 1)
    #expect(await auditWriter.health() == .degraded)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [
        .interactiveApproved,
        .interactiveRequested,
    ])
    #expect(page.gaps.droppedEventCount == 1)
}

@Test func runtimeInstallFailurePublishesTerminalWithoutStarted() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-interactive-runtime-fault-audit-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path
    )
    let auditWriter = BoundedInteractiveAuditWriterV0(store: auditStore)
    let runtime = DispatcherRuntime(failInstall: true)
    let flow = try await pendingDispatcherFlow(
        runtime: runtime,
        auditWriter: auditWriter
    )
    let proof = try dispatcherProof(for: flow.challenge)

    let responseData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(
            monotonicNow: 1_010,
            wallNow: 1_724_000_000_010
        ),
        responseMessageID: WireUUID(UUID())
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: responseData
    )
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )

    #expect(error.body.code == "provider.unavailable")
    #expect(page.events.map(\.draft.code) == [
        .interactiveFailed,
        .interactiveApproved,
        .interactiveRequested,
    ])
    #expect(!page.events.map(\.draft.code).contains(.interactiveStarted))
    #expect(await runtime.installed.isEmpty)
    #expect(await flow.dispatcher.activeInteractiveSessionID == nil)
}

@Test func dispatcherDeniesMissingGrantVisibleAppDisplayOrUnlockedSession() async throws {
    let deniedSnapshots = [
        try dispatcherSnapshot(grants: []),
        try dispatcherSnapshot(visible: false),
        try dispatcherSnapshot(displayID: nil),
    ]
    for snapshot in deniedSnapshots {
        let admission = DispatcherAdmission([snapshot])
        let materials = DispatcherMaterials()
        let dispatcher = InteractiveSessionWireDispatcherV0(
            admission: admission,
            materials: materials,
            runtime: DispatcherRuntime()
        )
        let request = try WireEnvelope(
            messageID: WireUUID(UUID()),
            correlationID: nil,
            sentAtUnixMilliseconds: 1,
            body: try InteractiveSessionRequestBody(effects: [.view])
        )
        let data = try await dispatcher.dispatch(
            requestJSON: WireCodec.encode(request),
            context: dispatcherContext(),
            responseMessageID: WireUUID(UUID())
        )
        let error = try WireCodec.decode(
            WireEnvelope<ProtocolErrorResponseBody>.self,
            from: data
        )
        #expect(error.body.code == "policy.denied")
        #expect(error.correlationID == request.messageID)
        #expect(await materials.approvalCount == 0)
    }

    let lockedAdmission = DispatcherAdmission([try dispatcherSnapshot()])
    let lockedMaterials = DispatcherMaterials()
    let locked = InteractiveSessionWireDispatcherV0(
        admission: lockedAdmission,
        materials: lockedMaterials,
        runtime: DispatcherRuntime()
    )
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1,
        body: try InteractiveSessionRequestBody(effects: [.view])
    )
    let lockedData = try await locked.dispatch(
        requestJSON: WireCodec.encode(request),
        context: dispatcherContext(hostState: .userSessionLocked),
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: lockedData
    ).body.code == "policy.denied")
    #expect(await lockedMaterials.approvalCount == 0)
}

@Test func dispatcherRejectsProofCorrelationAndLiveRevisionChangesTerminally() async throws {
    let correlation = try await pendingDispatcherFlow()
    let validProof = try dispatcherProof(for: correlation.challenge)
    let wrongProof = try WireEnvelope(
        messageID: validProof.messageID,
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: validProof.sentAtUnixMilliseconds,
        body: validProof.body
    )
    let correlationData = try await correlation.dispatcher.dispatch(
        requestJSON: WireCodec.encode(wrongProof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: correlationData
    ).body.code == "auth.invalidProof")
    #expect(await !correlation.dispatcher.hasPendingApproval)
    #expect(await correlation.runtime.installed.isEmpty)

    let changed = try await pendingDispatcherFlow(snapshots: [
        try dispatcherSnapshot(),
        try dispatcherSnapshot(grantRevision: 6),
    ])
    let changedProof = try dispatcherProof(for: changed.challenge)
    let changedData = try await changed.dispatcher.dispatch(
        requestJSON: WireCodec.encode(changedProof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: changedData
    ).body.code == "policy.denied")
    #expect(await !changed.dispatcher.hasPendingApproval)
    #expect(await changed.runtime.installed.isEmpty)
}

@Test func dispatcherReturnsNoAcceptanceWhenRuntimeInstallationFails() async throws {
    let runtime = DispatcherRuntime(failInstall: true)
    let flow = try await pendingDispatcherFlow(runtime: runtime)
    let proof = try dispatcherProof(for: flow.challenge)
    let responseData = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    let response = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: responseData
    )
    #expect(response.body.code == "provider.unavailable")
    #expect(await flow.runtime.installed.isEmpty)
    #expect(await flow.dispatcher.activeInteractiveSessionID == nil)
    #expect(await !flow.dispatcher.hasPendingApproval)
}

@Test func dispatcherDisconnectClearsPendingAndTerminatesActiveExactlyOnce() async throws {
    let pending = try await pendingDispatcherFlow()
    await pending.dispatcher.primarySessionClosed()
    #expect(await !pending.dispatcher.hasPendingApproval)
    #expect(await pending.runtime.terminations.isEmpty)

    let active = try await pendingDispatcherFlow()
    let proof = try dispatcherProof(for: active.challenge)
    _ = try await active.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    await active.dispatcher.primarySessionClosed()
    await active.dispatcher.primarySessionClosed()
    #expect(await active.dispatcher.activeInteractiveSessionID == nil)
    #expect(await active.runtime.terminations == [
        .init(
            sessionID: dispatcherSessionID,
            connectionID: dispatcherConnectionID,
            reason: .clientDisconnected
        ),
    ])
}

@Test func unrelatedPrimaryDisconnectLeavesPendingAndActiveControlUnchanged()
    async throws
{
    let unrelatedConnectionID = Data(repeating: 0x7A, count: 16)
    let pending = try await pendingDispatcherFlow()
    await pending.dispatcher.primarySessionClosed(
        primaryConnectionID: unrelatedConnectionID
    )
    #expect(await pending.dispatcher.hasPendingApproval)
    #expect(await pending.runtime.terminations.isEmpty)

    let active = try await pendingDispatcherFlow()
    let proof = try dispatcherProof(for: active.challenge)
    _ = try await active.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    await active.dispatcher.primarySessionClosed(
        primaryConnectionID: unrelatedConnectionID
    )
    #expect(await active.dispatcher.activeInteractiveSessionID
        == dispatcherSessionID)
    #expect(await active.runtime.terminations.isEmpty)

    await active.dispatcher.primarySessionClosed(
        primaryConnectionID: dispatcherConnectionID
    )
    #expect(await active.dispatcher.activeInteractiveSessionID == nil)
    #expect(await active.runtime.terminations == [
        .init(
            sessionID: dispatcherSessionID,
            connectionID: dispatcherConnectionID,
            reason: .clientDisconnected
        ),
    ])
}

@Test func localAuthorityEndsOnlyTheExactlyBoundPendingApproval() async throws {
    let flow = try await pendingDispatcherFlow()
    let binding = InteractiveLocalAuthorityBindingV0(
        deviceID: dispatcherDeviceID,
        requestID: flow.request.messageID.rawValue,
        approvalID: flow.challenge.body.approvalID.rawValue,
        interactiveSessionID: nil
    )
    #expect(await !flow.dispatcher.endFromLocalAuthority(
        binding: .init(
            deviceID: dispatcherDeviceID,
            requestID: UUID(),
            approvalID: flow.challenge.body.approvalID.rawValue,
            interactiveSessionID: nil
        ),
        reason: .localSuspension
    ))
    #expect(await flow.dispatcher.hasPendingApproval)
    #expect(await flow.dispatcher.endFromLocalAuthority(
        binding: binding,
        reason: .localSuspension
    ))
    #expect(await !flow.dispatcher.hasPendingApproval)
    #expect(await flow.dispatcher.endFromLocalAuthority(
        binding: binding,
        reason: .localSuspension
    ))
    #expect(await flow.runtime.terminations.isEmpty)
}

@Test func localAuthorityClearsActiveBeforeOneIdempotentTermination() async throws {
    let flow = try await pendingDispatcherFlow()
    let proof = try dispatcherProof(for: flow.challenge)
    _ = try await flow.dispatcher.dispatch(
        requestJSON: WireCodec.encode(proof),
        context: dispatcherContext(monotonicNow: 1_010),
        responseMessageID: WireUUID(UUID())
    )
    let binding = InteractiveLocalAuthorityBindingV0(
        deviceID: dispatcherDeviceID,
        requestID: flow.request.messageID.rawValue,
        approvalID: flow.challenge.body.approvalID.rawValue,
        interactiveSessionID: dispatcherSessionID
    )
    #expect(await flow.dispatcher.endFromLocalAuthority(
        binding: binding,
        reason: .localSuspension
    ))
    #expect(await flow.dispatcher.activeInteractiveSessionID == nil)
    #expect(await flow.dispatcher.endFromLocalAuthority(
        binding: binding,
        reason: .localSuspension
    ))
    #expect(await flow.runtime.terminations == [
        .init(
            sessionID: dispatcherSessionID,
            connectionID: dispatcherConnectionID,
            reason: .localSuspension
        ),
    ])
}

@Test func dispatcherReservesRequestAcrossAdmissionAwaitAndDisconnect() async throws {
    let admission = SuspendingDispatcherAdmission(try dispatcherSnapshot())
    let materials = DispatcherMaterials()
    let runtime = DispatcherRuntime()
    let dispatcher = InteractiveSessionWireDispatcherV0(
        admission: admission,
        materials: materials,
        runtime: runtime
    )
    let firstRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1,
        body: try InteractiveSessionRequestBody(effects: [.view])
    )
    let first = Task {
        try await dispatcher.dispatch(
            requestJSON: WireCodec.encode(firstRequest),
            context: dispatcherContext(),
            responseMessageID: WireUUID(UUID())
        )
    }
    await admission.waitUntilStarted()

    let secondRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 2,
        body: try InteractiveSessionRequestBody(effects: [.view])
    )
    let secondData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(secondRequest),
        context: dispatcherContext(),
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: secondData
    ).body.code == "rateLimit.exceeded")

    await dispatcher.primarySessionClosed()
    await admission.resume()
    let firstData = try await first.value
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: firstData
    ).body.code == "policy.denied")
    #expect(await !dispatcher.hasPendingApproval)
    #expect(await dispatcher.activeInteractiveSessionID == nil)
    #expect(await materials.approvalCount == 0)
}

@Test func dispatcherCompensatesWhenDisconnectRacesRuntimeInstallation() async throws {
    let runtime = SuspendingDispatcherRuntime()
    let admission = DispatcherAdmission([try dispatcherSnapshot()])
    let dispatcher = InteractiveSessionWireDispatcherV0(
        admission: admission,
        materials: DispatcherMaterials(),
        runtime: runtime
    )
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_724_000_000_000,
        body: try InteractiveSessionRequestBody(
            effects: [.view, .pointer, .keyboard, .text]
        )
    )
    let challengeData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(request),
        context: dispatcherContext(),
        responseMessageID: WireUUID(UUID())
    )
    let challenge = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalChallengeBody>.self,
        from: challengeData
    )
    let proof = try dispatcherProof(for: challenge)
    let approving = Task {
        try await dispatcher.dispatch(
            requestJSON: WireCodec.encode(proof),
            context: dispatcherContext(monotonicNow: 1_010),
            responseMessageID: WireUUID(UUID())
        )
    }
    await runtime.waitUntilStarted()

    await dispatcher.primarySessionClosed()
    await runtime.resume()
    let resultData = try await approving.value
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: resultData
    ).body.code == "auth.invalidProof")
    #expect(await runtime.liveSessionIDs.isEmpty)
    #expect(await runtime.logicalTerminationCount == 1)
    #expect(await dispatcher.activeInteractiveSessionID == nil)
}
