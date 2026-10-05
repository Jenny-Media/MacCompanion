import CompanionAuthentication
import CompanionDomain
import CompanionHost
import CompanionHostSession
import CompanionInteractiveWire
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionTestSupport
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let sessionHostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
private let sessionDeviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
private let sessionClientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let sessionPairingID = UUID(uuidString: "018f4000-0000-7000-8000-000000000001")!

private struct SessionFixture {
    let directory: URL
    let store: SQLiteSecurityStore
    let clientKey: P256.Signing.PrivateKey
    let hostFingerprint: Data
    let tlsBinding: HostApplicationTLSBinding

    static func create() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccompanion-session-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let store = try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        )
        let clientKey = P256.Signing.PrivateKey()
        let approvalKey = P256.Signing.PrivateKey()
        try await store.commitPairing(
            pairingID: sessionPairingID,
            record: try StoredDeviceRecord(
                deviceID: sessionDeviceID,
                clientID: sessionClientID,
                sessionPublicKeyX963: clientKey.publicKey.x963Representation,
                approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
                authorization: DeviceAuthorization(
                    state: .activeMonitorOnly,
                    authorizationEpoch: .init(rawValue: 1),
                    grantRevision: .init(rawValue: 1)
                ),
                policyRevision: .init(rawValue: 1),
                createdAtUnixMilliseconds: 1_000,
                updatedAtUnixMilliseconds: 1_000
            )
        )
        let hostKey = P256.Signing.PrivateKey()
        let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
            publicKeyX963: hostKey.publicKey.x963Representation
        )
        let hostFingerprint = try CompanionSecurityV0.hostFingerprint(
            subjectPublicKeyInfoDER: spki
        )
        return try Self(
            directory: directory,
            store: store,
            clientKey: clientKey,
            hostFingerprint: hostFingerprint,
            tlsBinding: HostApplicationTLSBinding(
                evidence: HostTLSListenerEvidence(
                    negotiatedTLSMajor: 1,
                    negotiatedTLSMinor: 3,
                    earlyDataAccepted: false,
                    servedSubjectPublicKeyInfoDER: spki
                ),
                requiredHostFingerprint: hostFingerprint
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FixedStatusClock: HostStatusClock {
    var value: Int64 = 5_000
    func nowUnixMilliseconds() -> Int64 { value }
}

private struct FixedSessionAuditClock: PrimarySessionAuditWallClockV0 {
    let value: Int64
    func nowUnixMilliseconds() -> Int64 { value }
}

private struct FixedStatusSampler: HostSystemSampling {
    func sample() async throws -> HostSystemMeasurement {
        try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 60,
            cpuUtilizationBasisPoints: 1_000,
            memoryTotalBytes: 16_000,
            memoryUsedBytes: 8_000,
            storageTotalBytes: 100_000,
            storageAvailableBytes: 50_000,
            powerSource: .ac,
            batteryLevelPercent: nil
        )
    }
}

private actor AcceptingStatusCommitter: StatusSequenceCommitting {
    func commit(
        expected: StatusSequenceState,
        replacement: StatusSequenceState
    ) async throws {}
}

private actor FixedStatusProvider: HostStatusSnapshotProvidingV0 {
    private(set) var requestCount = 0
    private let authority: HostStatusAuthority

    init() throws {
        authority = try HostStatusAuthority(
            hostID: sessionHostID,
            sequence: StatusSequenceState(
                generation: UUID(
                    uuidString: "018f3000-0000-7000-8000-000000000001"
                )!
            ),
            sampler: FixedStatusSampler(),
            clock: FixedStatusClock(),
            sequenceCommitter: AcceptingStatusCommitter()
        )
    }

    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        requestCount += 1
        return try await authority.snapshot(hostState: hostState)
    }
}

private enum FailingStatusProviderError: Error {
    case unavailable
}

private actor FailOnceStatusProvider: HostStatusSnapshotProvidingV0 {
    private let fallback: FixedStatusProvider
    private var shouldFail = true

    init() throws {
        fallback = try FixedStatusProvider()
    }

    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        if shouldFail {
            shouldFail = false
            throw FailingStatusProviderError.unavailable
        }
        return try await fallback.snapshot(hostState: hostState)
    }
}

private actor RecordingOperationDispatcher: AuthenticatedOperationWireDispatchingV0 {
    private(set) var contexts: [AuthenticatedOperationCommandContextV0] = []

    func dispatch(
        requestJSON: Data,
        context: AuthenticatedOperationCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        contexts.append(context)
        let request = try WireCodec.decode(
            WireEnvelope<OperationStatusRequestBody>.self,
            from: requestJSON
        )
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: OperationStatusResponseBody(
                operationID: request.body.operationID,
                state: .queued,
                terminalCode: nil,
                result: nil
            )
        ))
    }
}

private actor EmptyCapabilityDispatcher: AuthenticatedCapabilityRegistryDispatchingV1 {
    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<CapabilityRegistryRequestBody>.self,
            from: requestJSON
        )
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: CapabilityRegistryResponseBody(
                registryGeneration: WireUUID(UUID()),
                grantRevision: Int64(principal.grantRevision.rawValue),
                policyRevision: Int64(principal.policyRevision.rawValue),
                capabilities: [],
                nextAfterCapabilityID: nil
            )
        ))
    }
}

private actor RecordingCapabilityDispatcher: AuthenticatedCapabilityRegistryDispatchingV1 {
    private(set) var principals: [AuthenticatedDevicePrincipal] = []

    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        principals.append(principal)
        let request = try WireCodec.decode(
            WireEnvelope<CapabilityRegistryRequestBody>.self,
            from: requestJSON
        )
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: CapabilityRegistryResponseBody(
                registryGeneration: WireUUID(UUID()),
                grantRevision: Int64(principal.grantRevision.rawValue),
                policyRevision: Int64(principal.policyRevision.rawValue),
                capabilities: [],
                nextAfterCapabilityID: nil
            )
        ))
    }
}

private actor RecordingAuditDispatcher: AuthenticatedAuditWireDispatchingV1 {
    private(set) var principals: [AuthenticatedDevicePrincipal] = []

    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        principals.append(principal)
        let request = try WireCodec.decode(
            WireEnvelope<AuditListRequestBodyV1>.self,
            from: requestJSON
        )
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: AuditListResponseBodyV1(
                events: [],
                nextBeforeSequence: nil,
                oldestVisibleSequence: nil,
                newestVisibleSequence: nil,
                gaps: AuditGapWireV1(
                    prunedThroughSequence: nil,
                    droppedEventCount: 0
                )
            )
        ))
    }
}

private actor RecordingInteractiveDispatcher: AuthenticatedInteractiveWireDispatchingV0 {
    private(set) var kinds: [WireMessageKind] = []
    private(set) var contexts: [AuthenticatedInteractiveCommandContextV0] = []
    private(set) var closeCount = 0

    func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let kind = try WireCodec.messageKind(from: requestJSON)
        let requestMessageID: WireUUID
        switch kind {
        case .interactiveSessionRequest:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveSessionRequestBody>.self,
                from: requestJSON
            ).messageID
        case .interactiveSessionApprove:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveApprovalProofBody>.self,
                from: requestJSON
            ).messageID
        case .interactiveInitialSurfaceRequest:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveInitialSurfaceRequestBodyV0>.self,
                from: requestJSON
            ).messageID
        case .interactiveInitialSurfaceAcknowledgement:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveInitialSurfaceAcknowledgementBodyV0>.self,
                from: requestJSON
            ).messageID
        case .interactiveSurfaceTargetsRequest:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceTargetsRequestBodyV0>.self,
                from: requestJSON
            ).messageID
        case .interactiveSurfaceSelect:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
                from: requestJSON
            ).messageID
        case .interactiveSurfaceAcknowledgement:
            requestMessageID = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self,
                from: requestJSON
            ).messageID
        default:
            throw AuthenticatedPrimarySessionErrorV0.unexpectedMessage(
                phase: .ready,
                kind: kind
            )
        }
        kinds.append(kind)
        contexts.append(context)
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: requestMessageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: try ProtocolErrorResponseBody(
                code: "auth.staleEpoch",
                retry: .afterUserAction
            )
        ))
    }

    func primarySessionClosed() async {
        closeCount += 1
    }
}

private actor RecordingRouteObservationPublisher:
    AuthenticatedRouteObservationPublishingV1
{
    struct Publication: Equatable, Sendable {
        let connectionID: Data
        let routeClass: ConfiguredRouteClassV1
        let observedAtMonotonicMilliseconds: UInt64
    }

    private(set) var publications: [Publication] = []
    private(set) var withdrawals: [Data] = []

    func publish(
        connectionID: Data,
        routeClass: ConfiguredRouteClassV1,
        observedAtMonotonicMilliseconds: UInt64
    ) async {
        publications.append(Publication(
            connectionID: connectionID,
            routeClass: routeClass,
            observedAtMonotonicMilliseconds:
                observedAtMonotonicMilliseconds
        ))
    }

    func withdraw(connectionID: Data) async {
        withdrawals.append(connectionID)
    }
}

private actor DesktopContextGateV1: AuthenticatedInteractiveWireDispatchingV0 {
    var contexts: [AuthenticatedInteractiveCommandContextV0] = []
    func authorizeDesktop(sessionID: UUID, context: AuthenticatedInteractiveCommandContextV0) {
        contexts.append(context)
    }
    func dispatch(requestJSON: Data, context: AuthenticatedInteractiveCommandContextV0, responseMessageID: WireUUID) throws -> Data {
        throw AuthenticatedPrimarySessionErrorV0.invalidConfiguration
    }
    func primarySessionClosed() {}
}

@Test func desktopTunnelPrimaryGateUsesAuthenticatedContextAndRejectsReplayAndClosedPrimary() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let gate = DesktopContextGateV1()
    let session = try makeSession(fixture: fixture, interactive: gate)
    let sessionID = UUID()
    let frame = try WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: DesktopTunnelBodyV1(tunnelID: UUID(), interactiveSessionID: sessionID, operation: .open, sequence: 0)))
    await #expect(throws: (any Error).self) {
        try await session.authorizeDesktop(sessionID: sessionID, request: frame, contextHostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_000, monotonicNowMilliseconds: 100)
    }
    #expect(await gate.contexts.isEmpty)
    let connectionID = try await completeAuthentication(session, fixture: fixture)
    try await session.authorizeDesktop(sessionID: sessionID, request: frame, contextHostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_000, monotonicNowMilliseconds: 200)
    let context = try #require(await gate.contexts.first)
    #expect(context.primaryConnectionID == connectionID)
    #expect(context.principal.deviceID == sessionDeviceID)
    #expect(context.hostID == sessionHostID)
    await #expect(throws: (any Error).self) {
        try await session.authorizeDesktop(sessionID: sessionID, request: frame, contextHostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_001, monotonicNowMilliseconds: 201)
    }
    let root = FixturePaths.authoritativeFixtures()
    let goldenQuery = try WireCodec.decode(WireEnvelope<DesktopTunnelBodyV1>.self,
        from: Data(contentsOf: root.appendingPathComponent("valid/desktop-window-query.json"))).body
    let queryFrame = try WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil,
        sentAtUnixMilliseconds: 5_001, body: DesktopTunnelBodyV1(tunnelID: goldenQuery.tunnelID.rawValue,
            interactiveSessionID: sessionID, operation: .windowQuery, sequence: goldenQuery.sequence, data: goldenQuery.data)))
    try await session.authorizeDesktop(sessionID: sessionID, request: queryFrame, contextHostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001, monotonicNowMilliseconds: 201)
    await #expect(throws: (any Error).self) {
        try await session.authorizeDesktop(sessionID: sessionID, request: queryFrame, contextHostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_002, monotonicNowMilliseconds: 202)
    }
    await session.close()
    await #expect(throws: (any Error).self) {
        try await session.authorizeDesktop(sessionID: sessionID, contextHostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_002, monotonicNowMilliseconds: 202)
    }
    #expect(await gate.contexts.count == 2)
}

private func makeSession(
    fixture: SessionFixture,
    authenticationReader: (any AuthenticationDeviceReader)? = nil,
    status: (any HostStatusSnapshotProvidingV0)? = nil,
    operations: RecordingOperationDispatcher = RecordingOperationDispatcher(),
    capabilities: any AuthenticatedCapabilityRegistryDispatchingV1 = EmptyCapabilityDispatcher(),
    audit: (any AuthenticatedAuditWireDispatchingV1)? = nil,
    interactive: any AuthenticatedInteractiveWireDispatchingV0 = RecordingInteractiveDispatcher(),
    routeObservationPublisher:
        (any AuthenticatedRouteObservationPublishingV1)? = nil,
    detailedAudit: (any PrimarySessionAuditWritingV0)? = nil,
    detailedAuditClock: any PrimarySessionAuditWallClockV0 =
        FixedSessionAuditClock(value: 5_000),
    statusResponseClock: any HostStatusClock = FixedStatusClock()
) throws -> AuthenticatedPrimarySessionV0 {
    let statusProvider: any HostStatusSnapshotProvidingV0
    if let status {
        statusProvider = status
    } else {
        statusProvider = try FixedStatusProvider()
    }
    return try AuthenticatedPrimarySessionV0(
        hostID: sessionHostID,
        tlsBinding: fixture.tlsBinding,
        acceptedAtMonotonicMilliseconds: 0,
        authentication: ApplicationAuthenticationAuthority(deviceReader: authenticationReader ?? fixture.store),
        status: statusProvider,
        operations: operations,
        capabilities: capabilities,
        audit: audit,
        interactive: interactive,
        routeObservationPublisher: routeObservationPublisher,
        detailedAudit: detailedAudit,
        detailedAuditWallClock: detailedAuditClock,
        statusResponseClock: statusResponseClock
    )
}

private func authenticate(
    _ session: AuthenticatedPrimarySessionV0,
    fixture: SessionFixture,
    proofCorrelationOverride: WireUUID? = nil
) async throws -> (connectionID: Data, proof: WireEnvelope<AuthProofBody>) {
    let clientNonce = Data((0x10...0x2f).map(UInt8.init))
    let hello = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 4_000,
        body: try AuthHelloBody(
            clientID: WireUUID(sessionClientID),
            clientNonce: WireBytes32(clientNonce)
        )
    )
    let challengeMessageID = WireUUID(UUID())
    let challengeData = try await session.receive(
        requestJSON: WireCodec.encode(hello),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 4_001,
        monotonicNowMilliseconds: 100,
        responseMessageID: challengeMessageID
    )
    let challenge = try WireCodec.decode(
        WireEnvelope<AuthChallengeBody>.self,
        from: challengeData
    )
    let signingInput = try CompanionSecurityV0.authenticationSigningInput(
        clientID: sessionClientID,
        connectionID: challenge.body.connectionID.rawValue,
        clientNonce: clientNonce,
        serverNonce: challenge.body.serverNonce.rawValue,
        hostFingerprint: fixture.hostFingerprint,
        selectedMajor: challenge.body.selectedVersion.major,
        selectedMinor: challenge.body.selectedVersion.minor
    )
    let signature = try fixture.clientKey.signature(for: signingInput)
        .rawRepresentation
    let proof = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proofCorrelationOverride ?? challengeMessageID,
        sentAtUnixMilliseconds: 4_002,
        body: AuthProofBody(signature: try WireBytes64(signature))
    )
    return (challenge.body.connectionID.rawValue, proof)
}

private func completeAuthentication(
    _ session: AuthenticatedPrimarySessionV0,
    fixture: SessionFixture
) async throws -> Data {
    let prepared = try await authenticate(session, fixture: fixture)
    let descriptionData = try await session.receive(
        requestJSON: WireCodec.encode(prepared.proof),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 4_003,
        monotonicNowMilliseconds: 101,
        responseMessageID: WireUUID(UUID())
    )
    let description = try WireCodec.decode(
        WireEnvelope<SessionDescriptionBody>.self,
        from: descriptionData
    )
    #expect(description.correlationID == prepared.proof.messageID)
    #expect(description.body.deviceID == WireUUID(sessionDeviceID))
    #expect(description.body.features == ["audit.readSelf", "status.snapshot"])
    #expect(await session.phase == .ready)
    return prepared.connectionID
}

@Test func authenticatedKeepaliveRevalidatesAndReturnsCorrelatedPong() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let session = try makeSession(fixture: fixture)
    _ = try await completeAuthentication(session, fixture: fixture)
    let ping = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 4_100,
        body: KeepalivePingBodyV0()
    )

    let responseData = try await session.receive(
        requestJSON: WireCodec.encode(ping),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 4_101,
        monotonicNowMilliseconds: 15_101,
        responseMessageID: WireUUID(UUID())
    )
    let pong = try WireCodec.decode(
        WireEnvelope<KeepalivePongBodyV0>.self,
        from: responseData
    )

    #expect(pong.correlationID == ping.messageID)
    #expect(await session.phase == .ready)
    #expect(await session.nextDeadlineMonotonicMilliseconds() == 60_101)
}

@Test(arguments: [Int64(5_007), 4_999, -1, WireLimits.maximumSafeInteger + 1])
func statusReplyUsesPostSamplingClockWithoutWeakeningFreshness(responseTime: Int64) async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let session = try makeSession(fixture: fixture,
        statusResponseClock: FixedStatusClock(value: responseTime))
    _ = try await completeAuthentication(session, fixture: fixture)
    let request = try WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil,
        sentAtUnixMilliseconds: 4_900, body: StatusSnapshotRequestBody())
    let data = try await session.receive(requestJSON: WireCodec.encode(request),
        hostState: .userSessionActive, wallNowUnixMilliseconds: 4_901,
        monotonicNowMilliseconds: 200, responseMessageID: WireUUID(UUID()))
    if responseTime == 5_007 {
        let response = try WireCodec.decode(WireEnvelope<StatusSnapshotBody>.self, from: data)
        #expect(response.correlationID == request.messageID)
        #expect(response.body.observedAtUnixMilliseconds == 5_000)
        #expect(response.sentAtUnixMilliseconds == 5_007)
    } else {
        let response = try WireCodec.decode(WireEnvelope<ProtocolErrorResponseBody>.self, from: data)
        #expect(response.correlationID == request.messageID)
        #expect(response.body.code == "provider.unavailable")
        #expect(response.body.retry == .backoff)
    }
    #expect(await session.phase == .ready)
}

@Test func authenticatedSessionAloneRoutesStatusAndActWithHostOwnedContext() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let status = try FixedStatusProvider()
    let operations = RecordingOperationDispatcher()
    let session = try makeSession(
        fixture: fixture,
        status: status,
        operations: operations
    )
    let connectionID = try await completeAuthentication(session, fixture: fixture)

    let statusRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: StatusSnapshotRequestBody()
    )
    let statusData = try await session.receive(
        requestJSON: WireCodec.encode(statusRequest),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    let statusResponse = try WireCodec.decode(
        WireEnvelope<StatusSnapshotBody>.self,
        from: statusData
    )
    #expect(statusResponse.correlationID == statusRequest.messageID)
    #expect(statusResponse.body.hostID == WireUUID(sessionHostID))

    let operationID = WireUUID(UUID())
    let operationRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_002,
        body: OperationStatusRequestBody(operationID: operationID)
    )
    let operationData = try await session.receive(
        requestJSON: WireCodec.encode(operationRequest),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_003,
        monotonicNowMilliseconds: 201,
        responseMessageID: WireUUID(UUID())
    )
    let operationResponse = try WireCodec.decode(
        WireEnvelope<OperationStatusResponseBody>.self,
        from: operationData
    )
    #expect(operationResponse.correlationID == operationRequest.messageID)
    #expect(operationResponse.body.operationID == operationID)
    let contexts = await operations.contexts
    #expect(contexts.count == 1)
    #expect(contexts[0].principal.deviceID == sessionDeviceID)
    #expect(contexts[0].primaryConnectionID == connectionID)
}

@Test func statusProviderFailureIsCorrelatedAndDoesNotCloseControlAuthority() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let status = try FailOnceStatusProvider()
    let interactive = RecordingInteractiveDispatcher()
    let session = try makeSession(
        fixture: fixture,
        status: status,
        interactive: interactive
    )
    _ = try await completeAuthentication(session, fixture: fixture)

    let failedRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: StatusSnapshotRequestBody()
    )
    let failedData = try await session.receive(
        requestJSON: WireCodec.encode(failedRequest),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    let failedResponse = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: failedData
    )

    #expect(failedResponse.correlationID == failedRequest.messageID)
    #expect(failedResponse.body.code == "provider.unavailable")
    #expect(failedResponse.body.retry == .backoff)
    #expect(await session.phase == .ready)
    #expect(await interactive.closeCount == 0)

    let retryRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_002,
        body: StatusSnapshotRequestBody()
    )
    let retryData = try await session.receive(
        requestJSON: WireCodec.encode(retryRequest),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_003,
        monotonicNowMilliseconds: 201,
        responseMessageID: WireUUID(UUID())
    )
    let retryResponse = try WireCodec.decode(
        WireEnvelope<StatusSnapshotBody>.self,
        from: retryData
    )

    #expect(retryResponse.correlationID == retryRequest.messageID)
    #expect(await session.phase == .ready)
    #expect(await interactive.closeCount == 0)
}

@Test func authenticatedSessionRoutesAndExpiresConfiguredRouteObservation() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let routes = RecordingRouteObservationPublisher()
    let session = try makeSession(
        fixture: fixture,
        routeObservationPublisher: routes
    )
    let connectionID = try await completeAuthentication(
        session,
        fixture: fixture
    )
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: try RouteObservationBodyV1(
            connectionID: WireBytes16(connectionID),
            configuredRouteID: WireBytes16(Data(0x50...0x5f)),
            routeClass: .privateDNS,
            observationSequence: 1
        )
    )
    let responseData = try await session.receive(
        requestJSON: WireCodec.encode(request),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    let response = try WireCodec.decode(
        WireEnvelope<RouteObservationAcknowledgementBodyV1>.self,
        from: responseData
    )

    #expect(response.correlationID == request.messageID)
    #expect(response.body.connectionID.rawValue == connectionID)
    #expect(response.body.routeClass == .privateDNS)
    #expect(await routes.publications == [
        .init(
            connectionID: connectionID,
            routeClass: .privateDNS,
            observedAtMonotonicMilliseconds: 200
        ),
    ])
    #expect(await session.nextDeadlineMonotonicMilliseconds() == 30_201)
    #expect(await !session.expireIfRequired(at: 30_200))
    #expect((await routes.withdrawals).isEmpty)
    #expect(await !session.expireIfRequired(at: 30_201))
    #expect(await routes.withdrawals == [connectionID])
    #expect(await session.phase == .ready)
    #expect(await session.nextDeadlineMonotonicMilliseconds() == 45_200)
}

@Test func routeObservationCannotSubstituteAuthenticatedConnection() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let routes = RecordingRouteObservationPublisher()
    let session = try makeSession(
        fixture: fixture,
        routeObservationPublisher: routes
    )
    let connectionID = try await completeAuthentication(
        session,
        fixture: fixture
    )
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: try RouteObservationBodyV1(
            connectionID: WireBytes16(Data(0x10...0x1f)),
            configuredRouteID: WireBytes16(Data(0x50...0x5f)),
            routeClass: .privateNetwork,
            observationSequence: 1
        )
    )

    await #expect(
        throws: AuthenticatedRouteObservationSessionErrorV1
            .connectionMismatch
    ) {
        _ = try await session.receive(
            requestJSON: WireCodec.encode(request),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_001,
            monotonicNowMilliseconds: 200,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await session.phase == .closed)
    #expect((await routes.publications).isEmpty)
    #expect(await routes.withdrawals == [connectionID])
}

@Test func authenticatedSessionRoutesInteractiveCommandsWithHostOwnedBinding() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let interactive = RecordingInteractiveDispatcher()
    let session = try makeSession(
        fixture: fixture,
        interactive: interactive
    )
    let connectionID = try await completeAuthentication(session, fixture: fixture)

    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: try InteractiveSessionRequestBody(
            effects: [.view, .pointer]
        )
    )
    let requestResponse = try await session.receive(
        requestJSON: WireCodec.encode(request),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: requestResponse
    ).correlationID == request.messageID)

    let proof = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 5_002,
        body: InteractiveApprovalProofBody(
            approvalID: WireUUID(UUID()),
            signature: WireBytes64(Data(repeating: 0x44, count: 64))
        )
    )
    let proofResponse = try await session.receive(
        requestJSON: WireCodec.encode(proof),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_003,
        monotonicNowMilliseconds: 201,
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: proofResponse
    ).correlationID == proof.messageID)

    let interactiveSessionID = WireUUID(UUID())
    let surfaceID = WireUUID(UUID())
    let initialRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_004,
        body: try InteractiveInitialSurfaceRequestBodyV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: .init(rawValue: 4),
            sequence: 1
        )
    )
    _ = try await session.receive(
        requestJSON: WireCodec.encode(initialRequest),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_005,
        monotonicNowMilliseconds: 202,
        responseMessageID: WireUUID(UUID())
    )
    let initialAck = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_006,
        body: try InteractiveInitialSurfaceAcknowledgementBodyV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: .init(rawValue: 4),
            activationID: WireUUID(UUID()),
            surfaceID: surfaceID,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            readyMediaSequence: 2,
            sequence: 2
        )
    )
    _ = try await session.receive(
        requestJSON: WireCodec.encode(initialAck),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_007,
        monotonicNowMilliseconds: 203,
        responseMessageID: WireUUID(UUID())
    )
    let targetsRequest = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_008,
        body: try InteractiveSurfaceTargetsRequestBodyV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: .init(rawValue: 4),
            sequence: 3
        )
    )
    _ = try await session.receive(
        requestJSON: WireCodec.encode(targetsRequest),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_009,
        monotonicNowMilliseconds: 204,
        responseMessageID: WireUUID(UUID())
    )
    let selection = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_008,
        body: try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: .init(rawValue: 4),
            currentSurfaceID: surfaceID,
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            targetKind: .desktop,
            targetToken: nil,
            sequence: 4
        )
    )
    let selectionResponse = try await session.receive(
        requestJSON: WireCodec.encode(selection),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_009,
        monotonicNowMilliseconds: 205,
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: selectionResponse
    ).correlationID == selection.messageID)

    let acknowledgement = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_010,
        body: try InteractiveSurfaceAcknowledgementBodyV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: .init(rawValue: 4),
            transitionID: WireUUID(UUID()),
            surfaceID: surfaceID,
            surfaceRevision: .init(rawValue: 2),
            coordinateSpaceRevision: .init(rawValue: 2),
            readyMediaSequence: 3,
            sequence: 5
        )
    )
    let acknowledgementResponse = try await session.receive(
        requestJSON: WireCodec.encode(acknowledgement),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_011,
        monotonicNowMilliseconds: 206,
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: acknowledgementResponse
    ).correlationID == acknowledgement.messageID)

    #expect(await interactive.kinds == [
        .interactiveSessionRequest, .interactiveSessionApprove,
        .interactiveInitialSurfaceRequest,
        .interactiveInitialSurfaceAcknowledgement,
        .interactiveSurfaceTargetsRequest,
        .interactiveSurfaceSelect, .interactiveSurfaceAcknowledgement,
    ])
    let contexts = await interactive.contexts
    #expect(contexts.count == 7)
    #expect(contexts[0].principal.clientID == sessionClientID)
    #expect(contexts[0].primaryConnectionID == connectionID)
    #expect(contexts[0].hostID == sessionHostID)
    #expect(contexts[0].hostFingerprint == fixture.hostFingerprint)
    #expect(contexts[0].hostState == .userSessionActive)
}

@Test func primaryClosureNotifiesInteractiveOwnerExactlyOnce() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let interactive = RecordingInteractiveDispatcher()
    let session = try makeSession(
        fixture: fixture,
        interactive: interactive
    )
    _ = try await completeAuthentication(session, fixture: fixture)

    await session.close()
    await session.close()

    #expect(await session.phase == .closed)
    #expect(await interactive.closeCount == 1)
}

private actor PausingSessionAuthenticationReader: AuthenticationDeviceReader {
    let store: SQLiteSecurityStore
    private var pauseNext = false
    private var waiter: CheckedContinuation<Void, Never>?
    var paused: Bool { waiter != nil }
    init(store: SQLiteSecurityStore) { self.store = store }
    func arm() { pauseNext = true }
    func release() { let pending = waiter; waiter = nil; pending?.resume() }
    func device(clientID: UUID) async throws -> StoredDeviceRecord? {
        let record = try await store.device(clientID: clientID)
        if pauseNext {
            pauseNext = false
            await withCheckedContinuation { waiter = $0 }
        }
        return record
    }
}

@Test(arguments: [false, true])
func primaryConcurrentRevalidationCannotRegressLivenessOrReviveClosedSession(close: Bool) async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let reader = PausingSessionAuthenticationReader(store: fixture.store)
    let operations = RecordingOperationDispatcher()
    let session = try makeSession(fixture: fixture, authenticationReader: reader, operations: operations)
    _ = try await completeAuthentication(session, fixture: fixture)
    func request() throws -> Data {
        try WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil,
            sentAtUnixMilliseconds: 5_000, body: OperationStatusRequestBody(operationID: WireUUID(UUID()))))
    }
    let early = try request()
    await reader.arm()
    let pending = Task {
        try await session.receive(requestJSON: early, hostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_000, monotonicNowMilliseconds: 200, responseMessageID: WireUUID(UUID()))
    }
    for _ in 0..<1_000 {
        if await reader.paused { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let paused = await reader.paused
    #expect(paused)
    guard paused else { await session.close(); await reader.release(); _ = await pending.result; return }
    if close {
        await session.close()
        await reader.release()
        await #expect(throws: AuthenticatedPrimarySessionErrorV0.unauthenticated) { _ = try await pending.value }
        #expect(await operations.contexts.isEmpty)
        #expect(await session.phase == .closed)
    } else {
        _ = try await session.receive(requestJSON: request(), hostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_000, monotonicNowMilliseconds: 400, responseMessageID: WireUUID(UUID()))
        let laterDeadline = await session.nextDeadlineMonotonicMilliseconds()
        await reader.release()
        _ = try await pending.value
        #expect(await session.nextDeadlineMonotonicMilliseconds() == laterDeadline)
        #expect(await operations.contexts.count == 2)
        await session.close()
    }
}

@Test func durableAuthorizationChangeClosesBeforeAnyFurtherDisclosure() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let status = try FixedStatusProvider()
    let session = try makeSession(fixture: fixture, status: status)
    _ = try await completeAuthentication(session, fixture: fixture)
    _ = try await fixture.store.transitionDevice(
        sessionDeviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 5_000
    )
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_001,
        body: StatusSnapshotRequestBody()
    )
    await #expect(throws: ApplicationAuthenticationError.authenticationFailed) {
        _ = try await session.receive(
            requestJSON: WireCodec.encode(request),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_002,
            monotonicNowMilliseconds: 200,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await session.phase == .closed)
    #expect(await status.requestCount == 0)
}

@Test func proofCorrelationMismatchIsTerminalAndConsumesNoReadySession() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let session = try makeSession(fixture: fixture)
    let prepared = try await authenticate(
        session,
        fixture: fixture,
        proofCorrelationOverride: WireUUID(UUID())
    )
    await #expect(
        throws: AuthenticatedPrimarySessionErrorV0.invalidAuthenticationCorrelation
    ) {
        _ = try await session.receive(
            requestJSON: WireCodec.encode(prepared.proof),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 4_003,
            monotonicNowMilliseconds: 101,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await session.phase == .closed)
}

@Test func duplicateOrWrongPhaseTrafficClosesThePrimarySession() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let wrongPhaseSession = try makeSession(fixture: fixture)
    let premature = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 4_000,
        body: StatusSnapshotRequestBody()
    )
    await #expect(throws: (any Error).self) {
        _ = try await wrongPhaseSession.receive(
            requestJSON: WireCodec.encode(premature),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 4_001,
            monotonicNowMilliseconds: 100,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await wrongPhaseSession.phase == .closed)

    let duplicateSession = try makeSession(fixture: fixture)
    _ = try await completeAuthentication(duplicateSession, fixture: fixture)
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: StatusSnapshotRequestBody()
    )
    let requestData = try WireCodec.encode(request)
    _ = try await duplicateSession.receive(
        requestJSON: requestData,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    await #expect(throws: TransportGuardError.duplicateMessage(request.messageID)) {
        _ = try await duplicateSession.receive(
            requestJSON: requestData,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 5_002,
            monotonicNowMilliseconds: 201,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await duplicateSession.phase == .closed)
}

@Test func authenticationAndAuthenticatedIdleDeadlinesCloseAtExactBoundary() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }

    let unauthenticatedTimer = try makeSession(fixture: fixture)
    #expect(await unauthenticatedTimer.nextDeadlineMonotonicMilliseconds() == 10_000)
    #expect(await !unauthenticatedTimer.expireIfRequired(at: 9_999))
    #expect(await unauthenticatedTimer.expireIfRequired(at: 10_000))
    #expect(await unauthenticatedTimer.phase == .closed)

    let unauthenticated = try makeSession(fixture: fixture)
    let hello = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 10_000,
        body: try AuthHelloBody(
            clientID: WireUUID(sessionClientID),
            clientNonce: WireBytes32(Data(repeating: 1, count: 32))
        )
    )
    await #expect(
        throws: AuthenticatedPrimarySessionErrorV0.authenticationDeadlineExceeded
    ) {
        _ = try await unauthenticated.receive(
            requestJSON: WireCodec.encode(hello),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 10_000,
            monotonicNowMilliseconds: 10_000,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await unauthenticated.phase == .closed)

    let authenticatedTimer = try makeSession(fixture: fixture)
    _ = try await completeAuthentication(authenticatedTimer, fixture: fixture)
    #expect(await authenticatedTimer.nextDeadlineMonotonicMilliseconds() == 45_101)
    #expect(await !authenticatedTimer.expireIfRequired(at: 45_100))
    #expect(await authenticatedTimer.expireIfRequired(at: 45_101))
    #expect(await authenticatedTimer.phase == .closed)

    let authenticated = try makeSession(fixture: fixture)
    _ = try await completeAuthentication(authenticated, fixture: fixture)
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 49_003,
        body: StatusSnapshotRequestBody()
    )
    await #expect(
        throws: AuthenticatedPrimarySessionErrorV0.authenticatedLivenessExpired
    ) {
        _ = try await authenticated.receive(
            requestJSON: WireCodec.encode(request),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 49_003,
            monotonicNowMilliseconds: 45_101,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await authenticated.phase == .closed)
}

@Test func capabilityDiscoveryUsesTheSameRevalidatedSessionPrincipal() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let capabilities = RecordingCapabilityDispatcher()
    let session = try makeSession(
        fixture: fixture,
        capabilities: capabilities
    )
    _ = try await completeAuthentication(session, fixture: fixture)
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: CapabilityRegistryRequestBody()
    )
    let responseData = try await session.receive(
        requestJSON: WireCodec.encode(request),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    let response = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryResponseBody>.self,
        from: responseData
    )
    #expect(response.correlationID == request.messageID)
    let principals = await capabilities.principals
    #expect(principals.count == 1)
    #expect(principals[0].deviceID == sessionDeviceID)
    #expect(principals[0].clientID == sessionClientID)
}

@Test func auditReadUsesTheSameRevalidatedSessionPrincipal() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let audit = RecordingAuditDispatcher()
    let session = try makeSession(fixture: fixture, audit: audit)
    _ = try await completeAuthentication(session, fixture: fixture)
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 5_000,
        body: AuditListRequestBodyV1(beforeSequence: nil, limit: 20)
    )
    let responseData = try await session.receive(
        requestJSON: WireCodec.encode(request),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 5_001,
        monotonicNowMilliseconds: 200,
        responseMessageID: WireUUID(UUID())
    )
    let response = try WireCodec.decode(
        WireEnvelope<AuditListResponseBodyV1>.self,
        from: responseData
    )
    #expect(response.correlationID == request.messageID)
    let principals = await audit.principals
    #expect(principals.count == 1)
    #expect(principals[0].deviceID == sessionDeviceID)
    #expect(principals[0].clientID == sessionClientID)
}

@Test func primarySessionAuditPublishesAuthenticatedOpenAndTeardownAfterClose() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: fixture.directory.appendingPathComponent("audit.sqlite3").path
    )
    let writer = BoundedPrimarySessionAuditWriterV0(store: auditStore)
    let interactive = RecordingInteractiveDispatcher()
    let session = try makeSession(
        fixture: fixture,
        interactive: interactive,
        detailedAudit: writer,
        detailedAuditClock: FixedSessionAuditClock(value: 5_123)
    )

    _ = try await completeAuthentication(session, fixture: fixture)
    await session.close()

    #expect(await interactive.closeCount == 1)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [
        .connectionClosed,
        .connectionOpened,
        .authenticationSucceeded,
    ])
    #expect(page.events.first?.draft.observedAtUnixMilliseconds == 5_123)
    #expect(page.events.allSatisfy {
        $0.draft.subjectDeviceID == sessionDeviceID
            && $0.draft.visibility == .subjectDevice
            && $0.draft.actor == .pairedDevice
    })
    #expect(await writer.health() == .healthy)
}

@Test func rejectedPrimaryProofIsLocalOnlyAndClosesWithoutSubjectLeak() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: fixture.directory.appendingPathComponent("audit.sqlite3").path
    )
    let writer = BoundedPrimarySessionAuditWriterV0(store: auditStore)
    let session = try makeSession(fixture: fixture, detailedAudit: writer)
    let prepared = try await authenticate(session, fixture: fixture)
    let rejected = try WireEnvelope(
        messageID: prepared.proof.messageID,
        correlationID: prepared.proof.correlationID,
        sentAtUnixMilliseconds: 4_002,
        body: AuthProofBody(
            signature: try WireBytes64(Data(repeating: 0, count: 64))
        )
    )

    await #expect(throws: ApplicationAuthenticationError.authenticationFailed) {
        _ = try await session.receive(
            requestJSON: WireCodec.encode(rejected),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 4_003,
            monotonicNowMilliseconds: 101,
            responseMessageID: WireUUID(UUID())
        )
    }

    #expect(await session.phase == .closed)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.count == 1)
    #expect(page.events.first?.draft.code == .authenticationRejected)
    #expect(page.events.first?.draft.visibility == .localOnly)
    #expect(page.events.first?.draft.actor == .agent)
    #expect(page.events.first?.draft.subjectDeviceID == nil)
    #expect(page.events.first?.draft.correlationID
        == prepared.proof.messageID.rawValue)
}

@Test func wrongPhaseProtocolTrafficCreatesOnlyLocalRejectionDetail() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: fixture.directory.appendingPathComponent("audit.sqlite3").path
    )
    let writer = BoundedPrimarySessionAuditWriterV0(store: auditStore)
    let session = try makeSession(fixture: fixture, detailedAudit: writer)
    let premature = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 4_000,
        body: StatusSnapshotRequestBody()
    )

    await #expect(throws: AuthenticatedPrimarySessionErrorV0.self) {
        _ = try await session.receive(
            requestJSON: WireCodec.encode(premature),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 4_001,
            monotonicNowMilliseconds: 100,
            responseMessageID: WireUUID(UUID())
        )
    }

    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.count == 1)
    #expect(page.events.first?.draft.code == .protocolRejected)
    #expect(page.events.first?.draft.visibility == .localOnly)
    #expect(page.events.first?.draft.subjectDeviceID == nil)
    #expect(page.events.first?.draft.correlationID == nil)
    #expect(await session.phase == .closed)
}

@Test func droppedSessionCloseAuditCannotDelayInteractiveTeardown() async throws {
    let fixture = try await SessionFixture.create()
    defer { fixture.remove() }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: fixture.directory.appendingPathComponent("audit.sqlite3").path,
        configuration: try AuditStoreConfigurationV0(
            logicalByteLimit: 16 * 1_024 * 1_024,
            retainedRowLimit: 50_000,
            retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
            rateLimitAttempts: 2,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    let writer = BoundedPrimarySessionAuditWriterV0(store: auditStore)
    let interactive = RecordingInteractiveDispatcher()
    let session = try makeSession(
        fixture: fixture,
        interactive: interactive,
        detailedAudit: writer
    )

    _ = try await completeAuthentication(session, fixture: fixture)
    await session.close()

    #expect(await session.phase == .closed)
    #expect(await interactive.closeCount == 1)
    #expect(await writer.health() == .degraded)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [
        .connectionOpened,
        .authenticationSucceeded,
    ])
    #expect(page.gaps.droppedEventCount == 1)
}
