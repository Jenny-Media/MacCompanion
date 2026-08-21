@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let actClientID = UUID(
    uuidString: "018fa000-0000-7000-8000-000000000001"
)!
private let actHostID = UUID(
    uuidString: "018fa000-0000-7000-8000-000000000002"
)!
private let actDeviceID = UUID(
    uuidString: "018fa000-0000-7000-8000-000000000003"
)!
private let actOperationID = WireUUID(UUID(
    uuidString: "018fa000-0000-7000-8000-000000000004"
)!)
private let actConnectionID = Data(0x10...0x1f)
private let actFingerprint = Data(0x20...0x3f)

private actor CapturingOperationSigner: ClientOperationApprovalSigningV1 {
    private(set) var inputs: [Data] = []
    var signature = Data(repeating: 0x5a, count: 64)

    func signOperationApprovalInput(_ input: Data) async throws -> Data {
        inputs.append(input)
        return signature
    }

    func captured() -> [Data] { inputs }
}

private actor SuspendedOperationSigner: ClientOperationApprovalSigningV1 {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var signatureContinuation: CheckedContinuation<Data, Never>?

    func signOperationApprovalInput(_ input: Data) async throws -> Data {
        started = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            signatureContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() {
        signatureContinuation?.resume(returning: Data(repeating: 0x6b, count: 64))
        signatureContinuation = nil
    }
}

private final class MutableOperationClock: @unchecked Sendable {
    var value: Int64
    init(_ value: Int64) { self.value = value }
}

private func actDescriptor() throws -> CapabilityDiscoveryDescriptorV1 {
    let parameters = try CapabilitySchemaV1.object(properties: [
        CapabilitySchemaPropertyV1(
            name: "muted",
            required: true,
            schema: .boolean()
        ),
    ])
    return try CapabilityDiscoveryDescriptorV1(CapabilityDescriptorV1(
        capabilityID: "maccompanion.system.setAudioMuted",
        schemaVersion: 1,
        providerID: "maccompanion.native.audio",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018fa100-0000-7000-8000-000000000001"
        )!,
        executionRevision: UUID(
            uuidString: "018fa100-0000-7000-8000-000000000002"
        )!,
        englishTitle: "Set audio mute",
        englishSummary: "Set the default audio output mute state.",
        parameterSchema: parameters,
        resultSchema: parameters,
        effects: CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .reversible,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: false,
            cancellation: .notApplicable
        )
    ))
}

private func actPairedHost() throws -> ClientDurablePairedHostV0 {
    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let pairingID = UUID()
    let identity = try ClientPreparedIdentityV0(
        pairingID: pairingID,
        clientID: actClientID,
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
    return try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: pairingID,
            clientID: actClientID,
            hostID: actHostID,
            deviceID: actDeviceID,
            hostFingerprint: actFingerprint,
            endpoints: [try EndpointCandidate(
                kind: .dns,
                value: "studio.example.test",
                port: 47_474
            )],
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 1)
        ),
        identity: identity
    )
}

private func actAuthenticatedSession() -> ClientAuthenticatedSessionV0 {
    ClientAuthenticatedSessionV0(
        clientID: actClientID,
        hostID: actHostID,
        deviceID: actDeviceID,
        connectionID: actConnectionID,
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 5),
        policyRevision: .init(rawValue: 6),
        hostState: .userSessionActive,
        features: ["capability.operations"],
        serverTimeUnixMilliseconds: 10_000
    )
}

private func actCatalog(
    grantRevision: Int64 = 5
) throws -> GrantedCapabilityCatalogV1 {
    GrantedCapabilityCatalogV1(
        registryGeneration: WireUUID(UUID()),
        grantRevision: grantRevision,
        policyRevision: 6,
        capabilities: [try actDescriptor()]
    )
}

private func actSession(
    signer: any ClientOperationApprovalSigningV1,
    clock: MutableOperationClock
) throws -> ClientOperationSessionV1 {
    try ClientOperationSessionV1(
        operationID: actOperationID,
        capabilityID: "maccompanion.system.setAudioMuted",
        pairedHost: actPairedHost(),
        authenticatedSession: actAuthenticatedSession(),
        catalog: actCatalog(),
        signer: signer,
        wallNowUnixMilliseconds: { clock.value }
    )
}

@Test func parameterDraftBuildsClosedDefaultsAndBoundsEveryEdit() throws {
    let nested = try CapabilitySchemaV1.object(properties: [
        CapabilitySchemaPropertyV1(
            name: "enabled",
            required: true,
            schema: .boolean()
        ),
        CapabilitySchemaPropertyV1(
            name: "mode",
            required: false,
            schema: .string(
                maximumUTF8Bytes: 8,
                allowedValues: ["quiet", "normal"]
            )
        ),
        CapabilitySchemaPropertyV1(
            name: "levels",
            required: true,
            schema: .array(
                maximumItems: 2,
                item: try .integer(minimum: 1, maximum: 3)
            )
        ),
    ])
    var draft = try ClientCapabilityParameterDraftV1(schema: nested)
    #expect(draft.value == .object([
        .init(key: "enabled", value: .boolean(false)),
        .init(key: "levels", value: .array([])),
    ]))

    try draft.includeOptionalProperty("mode")
    try draft.appendArrayItem(at: [.property("levels")])
    try draft.setValue(.integer(3), at: [.property("levels"), .index(0)])
    #expect(try draft.validatedParameters() == .object([
        .init(key: "enabled", value: .boolean(false)),
        .init(key: "levels", value: .array([.integer(3)])),
        .init(key: "mode", value: .string("quiet")),
    ]))
    #expect(throws: ClientCapabilityParameterDraftErrorV1.schemaViolation) {
        try draft.setValue(
            .integer(4),
            at: [.property("levels"), .index(0)]
        )
    }
    #expect(try draft.validatedParameters() == .object([
        .init(key: "enabled", value: .boolean(false)),
        .init(key: "levels", value: .array([.integer(3)])),
        .init(key: "mode", value: .string("quiet")),
    ]))
}

@Test func operationSessionBindsCatalogParametersApprovalAndResult() async throws {
    let signer = CapturingOperationSigner()
    let clock = MutableOperationClock(10_100)
    let session = try actSession(signer: signer, clock: clock)
    let invokeID = WireUUID(UUID())
    let invokeFrame = try await session.begin(
        parameters: .object([
            .init(key: "muted", value: .boolean(true)),
        ]),
        messageID: invokeID,
        sentAtUnixMilliseconds: 10_100
    )
    let invoke = try WireCodec.decode(
        WireEnvelope<OperationInvokeRequestBody>.self,
        from: invokeFrame
    )
    #expect(invoke.body.operationID == actOperationID)
    #expect(invoke.body.capabilityID == "maccompanion.system.setAudioMuted")
    #expect(await session.state == .awaitingInvokeReply)

    let approvalID = WireUUID(UUID())
    let digest = Data(repeating: 0x41, count: 32)
    let challengeBytes = Data(repeating: 0x42, count: 32)
    let approvalResponse = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: invokeID,
        sentAtUnixMilliseconds: 10_101,
        body: try OperationApprovalRequiredBody(
            operationID: actOperationID,
            approvalID: approvalID,
            operationDigest: WireBytes32(digest),
            serverChallenge: WireBytes32(challengeBytes),
            issuedAtUnixMilliseconds: 10_100,
            expiresAtUnixMilliseconds: 40_100
        )
    )
    let approveMessageID = WireUUID(UUID())
    let approvalEvent = try await session.acceptReply(
        WireCodec.encode(approvalResponse),
        approvalMessageID: approveMessageID,
        approvalSentAtUnixMilliseconds: 10_102
    )
    guard case let .approvalFrame(frame, prompt) = approvalEvent else {
        Issue.record("expected approval frame")
        return
    }
    #expect(prompt.operationID == actOperationID)
    #expect(prompt.capabilityTitle == "Set audio mute")
    let approve = try WireCodec.decode(
        WireEnvelope<OperationApproveRequestBody>.self,
        from: frame
    )
    #expect(approve.messageID == approveMessageID)
    #expect(approve.body.approvalID == approvalID)
    #expect(await signer.captured() == [try CompanionSecurityV0
        .operationApprovalSigningInput(
            hostFingerprint: actFingerprint,
            clientID: actClientID,
            primaryConnectionID: actConnectionID,
            approvalID: approvalID.rawValue,
            operationDigest: digest,
            serverChallenge: challengeBytes,
            issuedAtUnixMilliseconds: 10_100,
            expiresAtUnixMilliseconds: 40_100,
            selectedMajor: 0,
            selectedMinor: 1
        )])

    let status = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: approveMessageID,
        sentAtUnixMilliseconds: 10_103,
        body: try OperationStatusResponseBody(
            operationID: actOperationID,
            state: .succeeded,
            terminalCode: nil,
            result: .object([
                .init(key: "muted", value: .boolean(true)),
            ])
        )
    )
    #expect(try await session.acceptReply(WireCodec.encode(status))
        == .status(.succeeded(verifiedResult: .object([
            .init(key: "muted", value: .boolean(true)),
        ]))))
    #expect(await session.state == .terminal(.succeeded(
        verifiedResult: .object([
            .init(key: "muted", value: .boolean(true)),
        ])
    )))
}

@Test func operationSessionRejectsWrongFenceSchemaAndCorrelation() async throws {
    let signer = CapturingOperationSigner()
    let clock = MutableOperationClock(10_100)
    #expect(throws: ClientOperationSessionErrorV1.invalidConfiguration) {
        _ = try ClientOperationSessionV1(
            operationID: actOperationID,
            capabilityID: actDescriptor().capabilityID,
            pairedHost: actPairedHost(),
            authenticatedSession: actAuthenticatedSession(),
            catalog: actCatalog(grantRevision: 99),
            signer: signer,
            wallNowUnixMilliseconds: { clock.value }
        )
    }

    let session = try actSession(signer: signer, clock: clock)
    await #expect(throws: ClientOperationSessionErrorV1.parameterSchemaRejected) {
        _ = try await session.begin(
            parameters: .object([
                .init(key: "muted", value: .string("yes")),
            ]),
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 10_100
        )
    }

    let valid = try actSession(signer: signer, clock: clock)
    _ = try await valid.begin(
        parameters: .object([
            .init(key: "muted", value: .boolean(true)),
        ]),
        messageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 10_100
    )
    let wrong = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 10_101,
        body: try OperationStatusResponseBody(
            operationID: actOperationID,
            state: .queued,
            terminalCode: nil,
            result: nil
        )
    )
    await #expect(throws: ClientOperationSessionErrorV1.invalidCorrelation) {
        _ = try await valid.acceptReply(WireCodec.encode(wrong))
    }
    #expect(await valid.state == .invalidated)
}

@Test func invalidationWhilePresenceIsPendingDiscardsLateSignature() async throws {
    let signer = SuspendedOperationSigner()
    let clock = MutableOperationClock(10_100)
    let session = try actSession(signer: signer, clock: clock)
    let invokeID = WireUUID(UUID())
    _ = try await session.begin(
        parameters: .object([
            .init(key: "muted", value: .boolean(false)),
        ]),
        messageID: invokeID,
        sentAtUnixMilliseconds: 10_100
    )
    let approval = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: invokeID,
        sentAtUnixMilliseconds: 10_101,
        body: try OperationApprovalRequiredBody(
            operationID: actOperationID,
            approvalID: WireUUID(UUID()),
            operationDigest: WireBytes32(Data(repeating: 0x51, count: 32)),
            serverChallenge: WireBytes32(Data(repeating: 0x52, count: 32)),
            issuedAtUnixMilliseconds: 10_100,
            expiresAtUnixMilliseconds: 40_100
        )
    )
    let task = Task {
        try await session.acceptReply(
            WireCodec.encode(approval),
            approvalMessageID: WireUUID(UUID()),
            approvalSentAtUnixMilliseconds: 10_102
        )
    }
    await signer.waitUntilStarted()
    #expect(await session.state == .awaitingUserPresence)
    await session.invalidate()
    await signer.finish()
    await #expect(throws: ClientOperationSessionErrorV1.lateApproval) {
        _ = try await task.value
    }
    #expect(await session.state == .invalidated)
}

@Test func ambiguousDeliveryQueriesSameDurableOperationID() async throws {
    let session = try actSession(
        signer: CapturingOperationSigner(),
        clock: MutableOperationClock(10_100)
    )
    _ = try await session.begin(
        parameters: .object([
            .init(key: "muted", value: .boolean(true)),
        ]),
        messageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 10_100
    )
    try await session.markDeliveryUnknown()
    let statusID = WireUUID(UUID())
    let statusFrame = try await session.requestStatus(
        messageID: statusID,
        sentAtUnixMilliseconds: 10_200
    )
    let request = try WireCodec.decode(
        WireEnvelope<OperationStatusRequestBody>.self,
        from: statusFrame
    )
    #expect(request.body.operationID == actOperationID)

    let response = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: statusID,
        sentAtUnixMilliseconds: 10_201,
        body: try OperationStatusResponseBody(
            operationID: actOperationID,
            state: .queued,
            terminalCode: nil,
            result: nil
        )
    )
    #expect(try await session.acceptReply(WireCodec.encode(response))
        == .status(.pending(.queued)))
    #expect(await session.state == .observing(.queued))

    let secondStatusID = WireUUID(UUID())
    _ = try await session.requestStatus(
        messageID: secondStatusID,
        sentAtUnixMilliseconds: 10_202
    )
    let unknown = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: secondStatusID,
        sentAtUnixMilliseconds: 10_203,
        body: try ProtocolErrorResponseBody(
            code: "operation.outcomeUnknown",
            retry: .afterReconnect,
            safeArguments: .object([
                .init(
                    key: "operationID",
                    value: .string(actOperationID.description)
                ),
            ])
        )
    )
    guard case .remoteError = try await session.acceptReply(
        WireCodec.encode(unknown)
    ) else {
        Issue.record("expected bounded remote error")
        return
    }
    #expect(await session.state == .deliveryUnknown)
    let retry = try await session.requestStatus(
        messageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 10_204
    )
    #expect(try WireCodec.decode(
        WireEnvelope<OperationStatusRequestBody>.self,
        from: retry
    ).body.operationID == actOperationID)
}
