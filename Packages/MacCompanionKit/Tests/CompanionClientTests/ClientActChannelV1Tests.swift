@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let channelClientID = UUID(
    uuidString: "018fa200-0000-7000-8000-000000000001"
)!
private let channelHostID = UUID(
    uuidString: "018fa200-0000-7000-8000-000000000002"
)!
private let channelDeviceID = UUID(
    uuidString: "018fa200-0000-7000-8000-000000000003"
)!
private let channelConnectionID = Data(0x30...0x3f)
private let channelFingerprint = Data(0x40...0x5f)

private actor ChannelFrameSender: ClientAuthenticatedCommandSendingV1 {
    private var frames: [Data] = []
    private var shouldFailNext = false

    func sendAuthenticatedCommand(_ frame: Data) async throws {
        frames.append(frame)
        if shouldFailNext {
            shouldFailNext = false
            throw ChannelTestError.sendFailed
        }
    }

    func failNext() { shouldFailNext = true }
    func capturedFrames() -> [Data] { frames }
}

private actor ChannelApprovalSigner: ClientOperationApprovalSigningV1 {
    private var inputs: [Data] = []

    func signOperationApprovalInput(_ input: Data) async throws -> Data {
        inputs.append(input)
        return Data(repeating: 0x61, count: 64)
    }

    func capturedInputs() -> [Data] { inputs }
}

private actor SuspendedChannelApprovalSigner:
    ClientOperationApprovalSigningV1
{
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
        signatureContinuation?.resume(
            returning: Data(repeating: 0x62, count: 64)
        )
        signatureContinuation = nil
    }
}

private enum ChannelTestError: Error {
    case noMessageID
    case sendFailed
}

private final class ChannelTestEnvironment: @unchecked Sendable {
    private let lock = NSLock()
    private var messageIDs: [WireUUID]
    private var clock: Int64

    init(messageIDCount: Int = 32, clock: Int64 = 20_000) {
        messageIDs = (0..<messageIDCount).map { index in
            WireUUID(UUID(uuidString: String(
                format: "018fa300-0000-7000-8000-%012x",
                index + 1
            ))!)
        }
        self.clock = clock
    }

    func nextMessageID() throws -> WireUUID {
        lock.lock()
        defer { lock.unlock() }
        guard !messageIDs.isEmpty else { throw ChannelTestError.noMessageID }
        return messageIDs.removeFirst()
    }

    func now() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return clock
    }

    var value: ClientActChannelEnvironmentV1 {
        ClientActChannelEnvironmentV1(
            makeMessageID: { try self.nextMessageID() },
            wallNowUnixMilliseconds: { self.now() }
        )
    }
}

private func channelPairedHost() throws -> ClientDurablePairedHostV0 {
    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let pairingID = UUID()
    return try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: pairingID,
            clientID: channelClientID,
            hostID: channelHostID,
            deviceID: channelDeviceID,
            hostFingerprint: channelFingerprint,
            endpoints: [try EndpointCandidate(
                kind: .dns,
                value: "act.example.test",
                port: 47_474
            )],
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 1)
        ),
        identity: try ClientPreparedIdentityV0(
            pairingID: pairingID,
            clientID: channelClientID,
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
}

private func channelAuthenticatedSession() -> ClientAuthenticatedSessionV0 {
    ClientAuthenticatedSessionV0(
        clientID: channelClientID,
        hostID: channelHostID,
        deviceID: channelDeviceID,
        connectionID: channelConnectionID,
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 5),
        policyRevision: .init(rawValue: 6),
        hostState: .userSessionActive,
        features: ["capability.operations"],
        serverTimeUnixMilliseconds: 20_000
    )
}

private func channelDescriptor(_ index: Int) throws
    -> CapabilityDiscoveryDescriptorV1
{
    let schema = try CapabilitySchemaV1.object(properties: [
        CapabilitySchemaPropertyV1(
            name: "enabled",
            required: true,
            schema: .boolean()
        ),
    ])
    return try CapabilityDiscoveryDescriptorV1(CapabilityDescriptorV1(
        capabilityID: String(
            format: "maccompanion.test.channelCapability%02d",
            index
        ),
        schemaVersion: 1,
        providerID: "maccompanion.test.channel",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018fa400-0000-7000-8000-000000000001"
        )!,
        executionRevision: UUID(
            uuidString: "018fa400-0000-7000-8000-000000000002"
        )!,
        englishTitle: "Channel capability \(index)",
        englishSummary: "A bounded channel capability.",
        parameterSchema: schema,
        resultSchema: schema,
        effects: CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .reversible,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: false,
            cancellation: .bestEffort
        )
    ))
}

private func channelPage(
    generation: WireUUID,
    range: Range<Int>,
    next: String?
) throws -> CapabilityRegistryResponseBody {
    try CapabilityRegistryResponseBody(
        registryGeneration: generation,
        grantRevision: 5,
        policyRevision: 6,
        capabilities: try range.map(channelDescriptor),
        nextAfterCapabilityID: next
    )
}

private func channelResponse<Body: WireBody>(
    correlationID: WireUUID,
    body: Body
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: correlationID,
        sentAtUnixMilliseconds: 20_001,
        body: body
    ))
}

private func makeChannel(
    signer: any ClientOperationApprovalSigningV1,
    sender: ChannelFrameSender,
    environment: ChannelTestEnvironment = ChannelTestEnvironment()
) throws -> ClientActChannelV1 {
    try ClientActChannelV1(
        pairedHost: channelPairedHost(),
        authenticatedSession: channelAuthenticatedSession(),
        signer: signer,
        sender: sender,
        environment: environment.value
    )
}

private func loadSinglePageCatalog(
    channel: ClientActChannelV1,
    sender: ChannelFrameSender
) async throws {
    try await channel.reloadCatalog()
    let requestFrame = try #require(await sender.capturedFrames().last)
    let request = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryRequestBody>.self,
        from: requestFrame
    )
    let event = try await channel.receive(channelResponse(
        correlationID: request.messageID,
        body: channelPage(
            generation: WireUUID(UUID()),
            range: 0..<1,
            next: nil
        )
    ))
    guard case .catalogPublished = event else {
        Issue.record("Expected an atomically published catalog")
        return
    }
}

@Test func actChannelPublishesOnlyAfterExactlyCorrelatedPagination()
    async throws
{
    let sender = ChannelFrameSender()
    let signer = ChannelApprovalSigner()
    let channel = try makeChannel(signer: signer, sender: sender)
    let generation = WireUUID(UUID())

    try await channel.reloadCatalog()
    let firstRequestFrame = try #require(await sender.capturedFrames().last)
    let firstRequest = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryRequestBody>.self,
        from: firstRequestFrame
    )
    let firstEvent = try await channel.receive(channelResponse(
        correlationID: firstRequest.messageID,
        body: channelPage(
            generation: generation,
            range: 0..<4,
            next: "maccompanion.test.channelCapability03"
        )
    ))
    #expect(firstEvent == nil)
    #expect(await channel.catalog == nil)
    #expect(await channel.state == .loadingCatalog)

    let frames = await sender.capturedFrames()
    #expect(frames.count == 2)
    let continuation = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryRequestBody>.self,
        from: frames[1]
    )
    #expect(continuation.body.expectedRegistryGeneration == generation)
    #expect(continuation.body.expectedGrantRevision == 5)
    #expect(
        continuation.body.afterCapabilityID
            == "maccompanion.test.channelCapability03"
    )

    let finalEvent = try await channel.receive(channelResponse(
        correlationID: continuation.messageID,
        body: channelPage(
            generation: generation,
            range: 4..<5,
            next: nil
        )
    ))
    guard case let .catalogPublished(catalog) = finalEvent else {
        Issue.record("Expected final catalog publication")
        return
    }
    #expect(catalog.capabilities.count == 5)
    #expect(await channel.state == .ready)
}

@Test func actChannelInvalidatesOnWrongCatalogCorrelation() async throws {
    let sender = ChannelFrameSender()
    let channel = try makeChannel(
        signer: ChannelApprovalSigner(),
        sender: sender
    )
    try await channel.reloadCatalog()

    await #expect(throws: ClientActChannelErrorV1.invalidCorrelation) {
        try await channel.receive(channelResponse(
            correlationID: WireUUID(UUID()),
            body: channelPage(
                generation: WireUUID(UUID()),
                range: 0..<1,
                next: nil
            )
        ))
    }
    #expect(await channel.state == .invalidated)
    #expect(await channel.catalog == nil)
}

@Test func actChannelTagsCatalogRemoteErrorWithoutInventingOperationState()
    async throws
{
    let sender = ChannelFrameSender()
    let channel = try makeChannel(
        signer: ChannelApprovalSigner(),
        sender: sender
    )
    try await channel.reloadCatalog()
    let requestFrame = try #require(await sender.capturedFrames().last)
    let request = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryRequestBody>.self,
        from: requestFrame
    )
    let event = try await channel.receive(channelResponse(
        correlationID: request.messageID,
        body: try ProtocolErrorResponseBody(
            code: "capability.registryChanged",
            retry: .afterReconnect
        )
    ))

    guard case let .remoteError(requestKind, error) = event else {
        Issue.record("Expected a catalog-scoped remote error")
        return
    }
    #expect(requestKind == .catalog)
    #expect(error.code == "capability.registryChanged")
    #expect(await channel.state == .idle)
    #expect(await channel.operationState() == nil)
}

@Test func actChannelInvalidatesWhenContinuationCannotBeSent() async throws {
    let sender = ChannelFrameSender()
    let channel = try makeChannel(
        signer: ChannelApprovalSigner(),
        sender: sender
    )
    try await channel.reloadCatalog()
    let requestFrame = try #require(await sender.capturedFrames().last)
    let request = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryRequestBody>.self,
        from: requestFrame
    )
    await sender.failNext()

    await #expect(throws: ClientActChannelErrorV1.sendFailed) {
        try await channel.receive(channelResponse(
            correlationID: request.messageID,
            body: channelPage(
                generation: WireUUID(UUID()),
                range: 0..<4,
                next: "maccompanion.test.channelCapability03"
            )
        ))
    }
    #expect(await channel.state == .invalidated)
    #expect(await channel.catalog == nil)
}

@Test func actChannelRoutesApprovalStatusAndCancellationOnOneSender()
    async throws
{
    let sender = ChannelFrameSender()
    let signer = ChannelApprovalSigner()
    let channel = try makeChannel(signer: signer, sender: sender)
    try await loadSinglePageCatalog(channel: channel, sender: sender)

    let operationID = WireUUID(UUID())
    let beginEvent = try await channel.beginOperation(
        capabilityID: "maccompanion.test.channelCapability00",
        parameters: .object([
            .init(key: "enabled", value: .boolean(true)),
        ]),
        operationID: operationID
    )
    #expect(beginEvent == .operationState(.awaitingInvokeReply))
    let invokeFrame = try #require(await sender.capturedFrames().last)
    let invoke = try WireCodec.decode(
        WireEnvelope<OperationInvokeRequestBody>.self,
        from: invokeFrame
    )
    #expect(invoke.body.operationID == operationID)

    let approvalID = WireUUID(UUID())
    let approvalEvent = try await channel.receive(channelResponse(
        correlationID: invoke.messageID,
        body: try OperationApprovalRequiredBody(
            operationID: operationID,
            approvalID: approvalID,
            operationDigest: WireBytes32(Data(repeating: 0x51, count: 32)),
            serverChallenge: WireBytes32(Data(repeating: 0x52, count: 32)),
            issuedAtUnixMilliseconds: 20_000,
            expiresAtUnixMilliseconds: 50_000
        )
    ))
    guard case let .operationApprovalSubmitted(prompt) = approvalEvent else {
        Issue.record("Expected submitted approval")
        return
    }
    #expect(prompt.operationID == operationID)
    #expect(prompt.approvalID == approvalID)
    #expect(await signer.capturedInputs().count == 1)
    let approveFrame = try #require(await sender.capturedFrames().last)
    let approve = try WireCodec.decode(
        WireEnvelope<OperationApproveRequestBody>.self,
        from: approveFrame
    )
    #expect(approve.body.approvalID == approvalID)

    let queuedEvent = try await channel.receive(channelResponse(
        correlationID: approve.messageID,
        body: try OperationStatusResponseBody(
            operationID: operationID,
            state: .queued,
            terminalCode: nil,
            result: nil
        )
    ))
    #expect(queuedEvent == .operationState(.observing(.queued)))

    _ = try await channel.cancelOperation()
    let cancelFrame = try #require(await sender.capturedFrames().last)
    let cancel = try WireCodec.decode(
        WireEnvelope<OperationCancelRequestBody>.self,
        from: cancelFrame
    )
    #expect(cancel.body.operationID == operationID)
    let cancelledEvent = try await channel.receive(channelResponse(
        correlationID: cancel.messageID,
        body: try OperationStatusResponseBody(
            operationID: operationID,
            state: .cancelled,
            terminalCode: "operation.cancelled",
            result: nil
        )
    ))
    guard case .operationState(.terminal(.cancelled)) = cancelledEvent else {
        Issue.record("Expected authoritative cancellation")
        return
    }
    try await channel.finishOperation()
    #expect(await channel.state == .ready)
}

@Test func actChannelKeepsOperationIDAfterAmbiguousInvokeSend()
    async throws
{
    let firstSender = ChannelFrameSender()
    let signer = ChannelApprovalSigner()
    let first = try makeChannel(signer: signer, sender: firstSender)
    try await loadSinglePageCatalog(channel: first, sender: firstSender)
    await firstSender.failNext()
    let operationID = WireUUID(UUID())

    let event = try await first.beginOperation(
        capabilityID: "maccompanion.test.channelCapability00",
        parameters: .object([
            .init(key: "enabled", value: .boolean(true)),
        ]),
        operationID: operationID
    )
    #expect(event == .operationState(.deliveryUnknown))
    #expect(await first.operationState() == .deliveryUnknown)

    let secondSender = ChannelFrameSender()
    let second = try makeChannel(signer: signer, sender: secondSender)
    try await loadSinglePageCatalog(channel: second, sender: secondSender)
    let resumed = try await second.resumeOperationStatus(
        capabilityID: "maccompanion.test.channelCapability00",
        operationID: operationID
    )
    #expect(resumed == .operationState(.awaitingStatusReply))
    let statusFrame = try #require(await secondSender.capturedFrames().last)
    let status = try WireCodec.decode(
        WireEnvelope<OperationStatusRequestBody>.self,
        from: statusFrame
    )
    #expect(status.body.operationID == operationID)
    #expect(
        await secondSender.capturedFrames().compactMap {
            try? WireCodec.messageKind(from: $0)
        }.filter { $0 == .operationInvoke }.isEmpty
    )
}

@Test func actChannelInvalidationDiscardsLateApprovalSignature()
    async throws
{
    let sender = ChannelFrameSender()
    let signer = SuspendedChannelApprovalSigner()
    let channel = try makeChannel(signer: signer, sender: sender)
    try await loadSinglePageCatalog(channel: channel, sender: sender)
    let operationID = WireUUID(UUID())
    _ = try await channel.beginOperation(
        capabilityID: "maccompanion.test.channelCapability00",
        parameters: .object([
            .init(key: "enabled", value: .boolean(false)),
        ]),
        operationID: operationID
    )
    let invokeFrame = try #require(await sender.capturedFrames().last)
    let invoke = try WireCodec.decode(
        WireEnvelope<OperationInvokeRequestBody>.self,
        from: invokeFrame
    )
    let approvalResponse = try channelResponse(
        correlationID: invoke.messageID,
        body: OperationApprovalRequiredBody(
            operationID: operationID,
            approvalID: WireUUID(UUID()),
            operationDigest: WireBytes32(Data(repeating: 0x53, count: 32)),
            serverChallenge: WireBytes32(Data(repeating: 0x54, count: 32)),
            issuedAtUnixMilliseconds: 20_000,
            expiresAtUnixMilliseconds: 50_000
        )
    )
    let receiveTask = Task { try await channel.receive(approvalResponse) }
    await signer.waitUntilStarted()
    await channel.invalidate()
    await signer.finish()

    do {
        _ = try await receiveTask.value
        Issue.record("Late signature unexpectedly escaped invalidation")
    } catch let error as ClientActChannelErrorV1 {
        #expect(error == .invalidated)
    }
    #expect(await channel.state == .invalidated)
    #expect(await sender.capturedFrames().count == 2)
}
