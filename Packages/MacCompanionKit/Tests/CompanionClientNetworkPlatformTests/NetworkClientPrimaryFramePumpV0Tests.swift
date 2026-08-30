@testable import CompanionClient
@testable import CompanionClientNetworkPlatform
import CompanionDiscovery
import CompanionDomain
@testable import CompanionInteractiveClient
import CompanionInteractiveWire
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Dispatch
import Foundation
import Network
import Testing

private struct NetworkClientTestSigner: ClientSessionAuthenticationSigningV0 {
    func signAuthenticationInput(_ input: Data) async throws -> Data {
        Data(repeating: 1, count: 64)
    }
}

#if DEBUG
private actor NetworkClientInjectedSender: ClientAuthenticatedCommandSendingV1 {
    var frames: [Data] = []
    func sendAuthenticatedCommand(_ frame: Data) { frames.append(frame) }
}

@Test func injectedPrimaryBridgePreservesBindingAndTerminalGuards() async throws {
    for cancellation in [false, true] {
        let base = try makeNetworkClientPumpHarness()
        let bridge = NetworkClientPrimaryRouterBridgeV0(
            pairedHost: try networkClientPairedHost(clientID: await base.session.clientID,
                hostID: base.hostID, deviceID: base.deviceID, fingerprint: base.fingerprint),
            approvalSigner: NetworkClientOperationApprovalSignerV0(),
            monotonicNowNanoseconds: { 1_003_000_000 })
        let sender = NetworkClientInjectedSender()
        await #expect(throws: NetworkClientPrimaryRouterBridgeErrorV0.unavailable) {
            try await bridge.sendAuthenticatedCommand(Data([1]))
        }
        try await bridge.bindAuthenticatedTransport(sender)
        await #expect(throws: NetworkClientPrimaryRouterBridgeErrorV0.invalidState) {
            try await bridge.bindAuthenticatedTransport(sender)
        }
        await #expect(throws: NetworkClientPrimaryRouterBridgeErrorV0.invalidState) {
            try await bridge.bind(pump: base.pump)
        }
        try await bridge.sendAuthenticatedCommand(Data([2]))
        #expect(await sender.frames == [Data([2])])
        if cancellation { await bridge.cancel() } else { await bridge.primaryTerminated() }
        await #expect(throws: NetworkClientPrimaryRouterBridgeErrorV0.unavailable) {
            try await bridge.sendAuthenticatedCommand(Data([3]))
        }
        await #expect(throws: NetworkClientPrimaryRouterBridgeErrorV0.invalidState) {
            try await bridge.bindAuthenticatedTransport(sender)
        }
        #expect(await sender.frames == [Data([2])])
        #expect(await bridge.currentRouter() == nil)
    }
}
#endif

private enum NetworkClientFakeFrameIOError: Error {
    case sendFailed
}

private final class NetworkClientFakeFrameIOV0:
    NetworkClientPrimaryFrameIOV0,
    @unchecked Sendable
{
    typealias ReceiveCompletion = @Sendable (Data?, Bool, Bool) -> Void

    private let queue = DispatchQueue(
        label: "MacCompanionTests.ClientFakeFrameIO"
    )
    private var stateHandler: (@Sendable (
        NetworkClientPrimaryFrameIOStateV0
    ) -> Void)?
    private var receiveCompletion: ReceiveCompletion?
    private var sentStorage: [Data] = []
    private var cancelCountStorage = 0
    private var sendErrorStorage: (any Error)?
    private var failedSendNumberStorage: Int?

    var sent: [Data] { queue.sync { sentStorage } }
    var cancelCount: Int { queue.sync { cancelCountStorage } }
    var hasPendingReceive: Bool { queue.sync { receiveCompletion != nil } }

    func failSends() {
        queue.sync { sendErrorStorage = NetworkClientFakeFrameIOError.sendFailed }
    }

    func failSend(number: Int) {
        precondition(number > 0)
        queue.sync { failedSendNumberStorage = number }
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkClientPrimaryFrameIOStateV0
        ) -> Void
    ) {
        queue.sync { stateHandler = handler }
    }

    func receive(
        maximumLength: Int,
        completion: @escaping ReceiveCompletion
    ) {
        precondition(
            maximumLength
                == NetworkClientPrimaryFramePumpV0.maximumReceiveChunkBytes
        )
        queue.sync { receiveCompletion = completion }
    }

    func send(_ data: Data) async throws {
        let error: (any Error)? = queue.sync {
            if let sendErrorStorage { return sendErrorStorage }
            if failedSendNumberStorage == sentStorage.count + 1 {
                return NetworkClientFakeFrameIOError.sendFailed
            }
            sentStorage.append(data)
            return nil
        }
        if let error { throw error }
    }

    func cancel() {
        queue.sync { cancelCountStorage += 1 }
    }

    func updateState(_ state: NetworkClientPrimaryFrameIOStateV0) {
        let handler = queue.sync { stateHandler }
        handler?(state)
    }

    func deliver(
        _ data: Data?,
        isComplete: Bool = false,
        failed: Bool = false
    ) {
        let completion = queue.sync {
            let result = receiveCompletion
            receiveCompletion = nil
            return result
        }
        precondition(completion != nil, "no receive is pending")
        completion?(data, isComplete, failed)
    }
}

private actor NetworkClientPumpTerminalRecorderV0 {
    private(set) var values: [NetworkClientPrimaryTerminationReasonV0] = []

    func record(_ value: NetworkClientPrimaryTerminationReasonV0) {
        values.append(value)
    }
}

private actor NetworkClientPumpCommandRecorderV0 {
    private(set) var values: [Data] = []

    func record(_ value: Data) {
        values.append(value)
    }
}

private final class NetworkClientPumpAuthenticationRecorderV0:
    @unchecked Sendable
{
    private let queue = DispatchQueue(
        label: "MacCompanionTests.ClientAuthenticationRecorder"
    )
    private var valuesStorage: [ClientAuthenticatedSessionV0] = []

    var values: [ClientAuthenticatedSessionV0] {
        queue.sync { valuesStorage }
    }

    func record(_ value: ClientAuthenticatedSessionV0) {
        queue.sync { valuesStorage.append(value) }
    }
}

private final class NetworkClientPumpReadyRecorderV0: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "MacCompanionTests.ClientTrafficReadyRecorder"
    )
    private var countStorage = 0

    var count: Int { queue.sync { countStorage } }

    func record() {
        queue.sync { countStorage += 1 }
    }
}

private final class NetworkClientImmediateThenBlockingSleepV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var callCountStorage = 0

    var callCount: Int { lock.withLock { callCountStorage } }

    func sleep() async throws {
        let call = lock.withLock {
            callCountStorage += 1
            return callCountStorage
        }
        if call == 1 { return }
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
}

private final class NetworkClientPumpMessageIDSourceV0: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "MacCompanionTests.ClientRouteMessageIDs"
    )
    private var values: [WireUUID]

    init(_ values: [WireUUID]) {
        self.values = values
    }

    func next() -> WireUUID {
        queue.sync {
            precondition(!values.isEmpty, "route message ID source exhausted")
            return values.removeFirst()
        }
    }
}

private struct NetworkClientPumpHarnessV0 {
    let io: NetworkClientFakeFrameIOV0
    let pump: NetworkClientPrimaryFramePumpV0
    let session: ClientPrimarySessionV0
    let start: NetworkClientHandshakeStartV0
    let helloMessageID: WireUUID
    let hostID: UUID
    let deviceID: UUID
    let fingerprint: Data
    let authenticated: NetworkClientPumpAuthenticationRecorderV0
    let ready: NetworkClientPumpReadyRecorderV0
    let commands: NetworkClientPumpCommandRecorderV0
    let terminals: NetworkClientPumpTerminalRecorderV0
}

private func makeNetworkClientPumpHarness(
    configuredRoute: ClientConfiguredRouteRecordV1? = nil,
    routeMessageIDs: [WireUUID] = [WireUUID(UUID())],
    routeSleep: @escaping @Sendable (UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
    }
) throws
    -> NetworkClientPumpHarnessV0
{
    let spki = try networkClientSPKI()
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let handoff = try NetworkClientApplicationTLSHandoffV0(
        evidence: TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
    let hostID = UUID()
    let deviceID = UUID()
    let session = try ClientPrimarySessionV0(
        clientID: UUID(),
        expectedHostID: hostID,
        expectedDeviceID: deviceID,
        requiredHostFingerprint: fingerprint,
        signer: NetworkClientTestSigner(),
        configuredRoute: configuredRoute
    )
    let io = NetworkClientFakeFrameIOV0()
    let terminals = NetworkClientPumpTerminalRecorderV0()
    let commands = NetworkClientPumpCommandRecorderV0()
    let authenticated = NetworkClientPumpAuthenticationRecorderV0()
    let ready = NetworkClientPumpReadyRecorderV0()
    let routeMessageIDSource = NetworkClientPumpMessageIDSourceV0(
        routeMessageIDs
    )
    let helloMessageID = WireUUID(UUID())
    let pump = NetworkClientPrimaryFramePumpV0(
        io: io,
        tlsHandoff: handoff,
        session: session,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 2_001,
                monotonicNowMilliseconds: 1_003
            )
        },
        authenticated: { authenticated.record($0) },
        readyForAuthenticatedTraffic: { ready.record() },
        receivedCommand: { await commands.record($0) },
        routeMessageID: { routeMessageIDSource.next() },
        routeSleep: routeSleep,
        terminal: { reason in
            Task { await terminals.record(reason) }
        }
    )
    return try NetworkClientPumpHarnessV0(
        io: io,
        pump: pump,
        session: session,
        start: NetworkClientHandshakeStartV0(
            clientNonce: WireBytes32(Data(repeating: 0x33, count: 32)),
            helloMessageID: helloMessageID,
            proofMessageID: WireUUID(UUID()),
            wallNowUnixMilliseconds: 2_000,
            monotonicNowMilliseconds: 1_002
        ),
        helloMessageID: helloMessageID,
        hostID: hostID,
        deviceID: deviceID,
        fingerprint: fingerprint,
        authenticated: authenticated,
        ready: ready,
        commands: commands,
        terminals: terminals
    )
}

private func waitForNetworkClientSentCount(
    _ io: NetworkClientFakeFrameIOV0,
    _ expectedCount: Int
) async -> [Data] {
    for _ in 0..<1_000 {
        let values = io.sent
        if values.count >= expectedCount { return values }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return io.sent
}

private func waitForNetworkClientPendingReceive(
    _ io: NetworkClientFakeFrameIOV0
) async -> Bool {
    for _ in 0..<1_000 {
        if io.hasPendingReceive { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return io.hasPendingReceive
}

private func waitForNetworkClientCommandCount(
    _ recorder: NetworkClientPumpCommandRecorderV0,
    _ expectedCount: Int
) async -> [Data] {
    for _ in 0..<1_000 {
        let values = await recorder.values
        if values.count >= expectedCount { return values }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await recorder.values
}

private func decodeNetworkClientSentFrame<Body: WireBody>(
    _ framed: Data,
    as body: Body.Type = Body.self
) throws -> WireEnvelope<Body> {
    var decoder = LengthPrefixedFrameDecoder()
    let frames = try decoder.append(framed)
    return try WireCodec.decode(
        WireEnvelope<Body>.self,
        from: #require(frames.first)
    )
}

private func authenticateNetworkClientPump(
    _ harness: NetworkClientPumpHarnessV0
) async throws {
    try await harness.pump.beginOnVerifiedReadyConnection(harness.start)
    let hello = try decodeNetworkClientSentFrame(
        #require(harness.io.sent.first),
        as: AuthHelloBody.self
    )
    let challenge = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: hello.messageID,
        sentAtUnixMilliseconds: 2_001,
        body: try AuthChallengeBody(
            connectionID: WireBytes16(Data(repeating: 0x11, count: 16)),
            serverNonce: WireBytes32(Data(repeating: 0x22, count: 32)),
            hostFingerprint: WireFingerprint(harness.fingerprint)
        )
    )
    harness.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(challenge))
    )
    _ = await waitForNetworkClientSentCount(harness.io, 2)
    let proof = try decodeNetworkClientSentFrame(
        harness.io.sent[1],
        as: AuthProofBody.self
    )
    let description = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proof.messageID,
        sentAtUnixMilliseconds: 2_003,
        body: try SessionDescriptionBody(
            hostID: WireUUID(harness.hostID),
            deviceID: WireUUID(harness.deviceID),
            deviceState: .activeGranted,
            authorizationEpoch: .init(rawValue: 2),
            grantRevision: .init(rawValue: 3),
            policyRevision: .init(rawValue: 4),
            hostState: .userSessionActive,
            features: ["status.snapshot"],
            serverTimeUnixMilliseconds: 2_003
        )
    )
    harness.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(description))
    )
}

private func waitForNetworkClientPumpTerminal(
    _ recorder: NetworkClientPumpTerminalRecorderV0
) async -> [NetworkClientPrimaryTerminationReasonV0] {
    for _ in 0..<1_000 {
        let values = await recorder.values
        if !values.isEmpty { return values }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await recorder.values
}

private func networkClientSPKI() throws -> Data {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 1
    let key = try P256.Signing.PrivateKey(rawRepresentation: scalar)
    return try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
}

@Test func clientNetworkHandoffRequiresExactLivePinProfile() throws {
    let spki = try networkClientSPKI()
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let evidence = TLSPeerEvidence(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 3,
        earlyDataAccepted: false,
        pinnedLeafPolicyAccepted: true,
        subjectPublicKeyInfoDER: spki
    )
    let handoff = try NetworkClientApplicationTLSHandoffV0(
        evidence: evidence,
        requiredHostFingerprint: fingerprint
    )
    #expect(handoff.hostFingerprint == fingerprint)

    #expect(throws: PinnedTLSAuthorityError.hostFingerprintMismatch) {
        _ = try NetworkClientApplicationTLSHandoffV0(
            evidence: evidence,
            requiredHostFingerprint: Data(repeating: 0, count: 32)
        )
    }
    #expect(throws: PinnedTLSAuthorityError.earlyDataAccepted) {
        _ = try NetworkClientApplicationTLSHandoffV0(
            evidence: TLSPeerEvidence(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: true,
                pinnedLeafPolicyAccepted: true,
                subjectPublicKeyInfoDER: spki
            ),
            requiredHostFingerprint: fingerprint
        )
    }
}

@Test func clientNetworkPumpConstructsWithoutStartingNetworkActivity() async throws {
    let spki = try networkClientSPKI()
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let handoff = try NetworkClientApplicationTLSHandoffV0(
        evidence: TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
    let session = try ClientPrimarySessionV0(
        clientID: UUID(),
        expectedHostID: UUID(),
        expectedDeviceID: UUID(),
        requiredHostFingerprint: fingerprint,
        signer: NetworkClientTestSigner()
    )
    let connection = NWConnection(
        host: "127.0.0.1",
        port: 9,
        using: .tcp
    )
    _ = NetworkClientPrimaryFramePumpV0(
        connection: connection,
        tlsHandoff: handoff,
        session: session,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 1,
                monotonicNowMilliseconds: 1
            )
        },
        receivedCommand: { _ in }
    )
    let phase = await session.phase
    #expect(phase == .awaitingTCP)
}

@Test func clientHandshakeStartRequiresDistinctIDsAndSafeClocks() throws {
    let messageID = WireUUID(UUID())
    #expect(throws: NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration) {
        _ = try NetworkClientHandshakeStartV0(
            clientNonce: WireBytes32(Data(repeating: 1, count: 32)),
            helloMessageID: messageID,
            proofMessageID: messageID,
            wallNowUnixMilliseconds: 1,
            monotonicNowMilliseconds: 1
        )
    }
    #expect(throws: NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration) {
        _ = try NetworkClientHandshakeStartV0(
            clientNonce: WireBytes32(Data(repeating: 1, count: 32)),
            helloMessageID: messageID,
            proofMessageID: WireUUID(UUID()),
            wallNowUnixMilliseconds: -1,
            monotonicNowMilliseconds: 1
        )
    }
}

@Test func clientPumpClassifiesOnlyClosedRemoteAuthErrorsAsDenial() {
    let denied = ClientPrimarySessionErrorV0.remoteError(
        code: "deviceSuspended",
        retry: .afterUserAction
    )
    #expect(
        NetworkClientPrimaryFramePumpV0.terminationReason(for: denied)
            == .authenticationDenied
    )
    #expect(
        NetworkClientPrimaryFramePumpV0.terminationReason(
            for: CocoaError(.fileReadCorruptFile)
        ) == .protocolOrSessionFailure
    )
}

@Test func clientPumpInjectedIOClosesOnInitialSendFailure() async throws {
    let harness = try makeNetworkClientPumpHarness()
    harness.io.failSends()

    await #expect(throws: NetworkClientFakeFrameIOError.sendFailed) {
        try await harness.pump.beginOnVerifiedReadyConnection(harness.start)
    }
    #expect(
        await waitForNetworkClientPumpTerminal(harness.terminals)
            == [.protocolOrSessionFailure]
    )
    #expect(harness.io.sent.isEmpty)
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func clientPumpInjectedIORejectsMalformedFrameAndCloses() async throws {
    let harness = try makeNetworkClientPumpHarness()
    try await harness.pump.beginOnVerifiedReadyConnection(harness.start)
    #expect(harness.io.sent.count == 1)
    var sentDecoder = LengthPrefixedFrameDecoder()
    let sentFrames = try sentDecoder.append(harness.io.sent[0])
    #expect(sentFrames.count == 1)
    let hello = try WireCodec.decode(
        WireEnvelope<AuthHelloBody>.self,
        from: sentFrames[0]
    )
    #expect(hello.messageID == harness.helloMessageID)

    harness.io.deliver(Data([0, 0, 0, 0]))

    #expect(
        await waitForNetworkClientPumpTerminal(harness.terminals)
            == [.protocolOrSessionFailure]
    )
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func clientPumpInjectedIOClassifiesFramedRemoteDenial() async throws {
    let harness = try makeNetworkClientPumpHarness()
    try await harness.pump.beginOnVerifiedReadyConnection(harness.start)
    let denial = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: harness.helloMessageID,
        sentAtUnixMilliseconds: 2_001,
        body: try ProtocolErrorResponseBody(
            code: "auth.deviceSuspended",
            retry: .afterUserAction
        )
    )

    harness.io.deliver(
        try LengthPrefixedFrameDecoder.encode(try WireCodec.encode(denial))
    )

    #expect(
        await waitForNetworkClientPumpTerminal(harness.terminals)
            == [.authenticationDenied]
    )
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func clientPumpInjectedIOTeardownIsExactlyOnceAfterReceiveFailure()
    async throws
{
    let harness = try makeNetworkClientPumpHarness()
    try await harness.pump.beginOnVerifiedReadyConnection(harness.start)

    harness.io.deliver(nil, failed: true)
    #expect(
        await waitForNetworkClientPumpTerminal(harness.terminals)
            == [.receiveFailed]
    )

    harness.io.updateState(.failed)
    harness.io.updateState(.cancelled)
    await harness.pump.cancel()
    await Task.yield()

    #expect(await harness.terminals.values == [.receiveFailed])
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func clientPumpPublishesAuthenticationAndOwnsConfiguredRouteHeartbeat()
    async throws
{
    let routeID = try WireBytes16(Data(0x50...0x5f))
    let configuredRoute = try ClientConfiguredRouteRecordV1(
        configuredRouteID: routeID,
        endpoint: EndpointCandidate(
            kind: .dns,
            value: "studio.example.net",
            port: 443
        ),
        provenance: .privateDNS
    )
    let initialMessageID = WireUUID(UUID())
    let heartbeatMessageID = WireUUID(UUID())
    let harness = try makeNetworkClientPumpHarness(
        configuredRoute: configuredRoute,
        routeMessageIDs: [initialMessageID, heartbeatMessageID],
        routeSleep: { nanoseconds in
            if nanoseconds == 15_000_000_000 { return }
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    )

    try await authenticateNetworkClientPump(harness)
    let initialSends = await waitForNetworkClientSentCount(harness.io, 3)
    #expect(initialSends.count == 3)
    #expect(harness.authenticated.values.count == 1)
    #expect(harness.ready.count == 1)
    #expect(harness.authenticated.values.first?.hostID == harness.hostID)
    let observation = try decodeNetworkClientSentFrame(
        initialSends[2],
        as: RouteObservationBodyV1.self
    )
    #expect(observation.messageID == initialMessageID)
    #expect(observation.body.configuredRouteID == routeID)
    #expect(observation.body.routeClass == .privateDNS)
    #expect(observation.body.observationSequence == 1)

    #expect(await waitForNetworkClientPendingReceive(harness.io))
    let unrelatedResponse = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 2_004,
        body: StatusSnapshotRequestBody()
    )
    let unrelatedData = try WireCodec.encode(unrelatedResponse)
    harness.io.deliver(
        try LengthPrefixedFrameDecoder.encode(unrelatedData)
    )
    #expect(
        await waitForNetworkClientCommandCount(harness.commands, 1)
            == [unrelatedData]
    )

    #expect(await waitForNetworkClientPendingReceive(harness.io))
    let acknowledgement = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: observation.messageID,
        sentAtUnixMilliseconds: 2_005,
        body: try RouteObservationAcknowledgementBodyV1(
            connectionID: observation.body.connectionID,
            configuredRouteID: observation.body.configuredRouteID,
            routeClass: observation.body.routeClass,
            observationSequence: observation.body.observationSequence
        )
    )
    harness.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(acknowledgement))
    )

    let heartbeatSends = await waitForNetworkClientSentCount(harness.io, 4)
    #expect(heartbeatSends.count == 4)
    let heartbeat = try decodeNetworkClientSentFrame(
        heartbeatSends[3],
        as: RouteObservationBodyV1.self
    )
    #expect(heartbeat.messageID == heartbeatMessageID)
    #expect(heartbeat.body.configuredRouteID == routeID)
    #expect(heartbeat.body.observationSequence == 2)
    #expect(await harness.terminals.values.isEmpty)
    #expect(await harness.session.phase == .authenticated)

    await harness.pump.cancel()
}

@Test func clientPumpNeverPublishesDeadRouteWhenInitialObservationSendFails()
    async throws
{
    let configuredRoute = try ClientConfiguredRouteRecordV1(
        configuredRouteID: WireBytes16(Data(0x60...0x6f)),
        endpoint: EndpointCandidate(
            kind: .dns,
            value: "mac.tailnet.ts.net",
            port: 47_474
        ),
        provenance: .privateNetwork
    )
    let harness = try makeNetworkClientPumpHarness(
        configuredRoute: configuredRoute
    )
    harness.io.failSend(number: 3)

    try await authenticateNetworkClientPump(harness)

    #expect(
        await waitForNetworkClientPumpTerminal(harness.terminals)
            == [.protocolOrSessionFailure]
    )
    #expect(harness.authenticated.values.count == 1)
    #expect(harness.ready.count == 0)
    #expect(harness.io.sent.count == 2)
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func clientConnectionStateDecisionWaitsOnlyForNonterminalStates() {
    #expect(
        NetworkClientConnectionStateDecisionV0.decide(.setup)
            == .continueWaiting
    )
    #expect(
        NetworkClientConnectionStateDecisionV0.decide(.preparing)
            == .continueWaiting
    )
    #expect(
        NetworkClientConnectionStateDecisionV0.decide(
            .waiting(.posix(.EAGAIN))
        ) == .continueWaiting
    )
    #expect(
        NetworkClientConnectionStateDecisionV0.decide(.ready) == .ready
    )
    #expect(
        NetworkClientConnectionStateDecisionV0.decide(
            .failed(.posix(.ECONNREFUSED))
        ) == .failed
    )
    #expect(
        NetworkClientConnectionStateDecisionV0.decide(.cancelled) == .failed
    )
}

@Test func invalidPinnedAttemptFailsBeforeStartingNetworkActivity() async throws {
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.1.20",
        port: 47_474
    )
    let validPin = Data(repeating: 1, count: 32)
    var reconnect = try ReconnectStateMachine(
        candidates: [endpoint],
        requiredHostFingerprint: validPin,
        foreground: true,
        networkReachable: true
    )
    let roundID = UUID()
    let effects = try reconnect.apply(.tick(
        monotonicNowMilliseconds: 1,
        roundID: roundID
    ))
    guard case let .startDialRound(round) = effects.first,
          let plannedAttempt = round.attempts.first else {
        Issue.record("missing planned attempt")
        return
    }
    let adapter = NetworkClientRouteAttemptV0(
        configuration: NetworkClientRouteAttemptConfigurationV0(
            clientID: UUID(),
            expectedHostID: UUID(),
            expectedDeviceID: UUID(),
            signer: NetworkClientTestSigner(),
            clock: {
                NetworkClientClockSnapshotV0(
                    wallNowUnixMilliseconds: 1,
                    monotonicNowMilliseconds: 1
                )
            },
            nonce: { try WireBytes32(Data(repeating: 2, count: 32)) },
            messageID: { WireUUID(UUID()) },
            pinnedLeafEvaluator: { _ in
                throw CocoaError(.fileReadCorruptFile)
            },
            verificationQueue: DispatchQueue(
                label: "MacCompanionTests.RouteVerification"
            ),
            connectionQueue: DispatchQueue(
                label: "MacCompanionTests.RouteConnection"
            ),
            receivedCommand: { _ in }
        )
    )
    guard case .authenticationDenied = await adapter.attempt(
        plannedAttempt,
        roundID: roundID,
        requiredHostFingerprint: Data(repeating: 1, count: 31)
    ) else {
        Issue.record("invalid pin must fail before creating a connection")
        return
    }
}

@Test func routeAttemptConfigurationBindsOnlyTheExactCatalogEndpoint() throws {
    let endpoint = try EndpointCandidate(
        kind: .dns,
        value: "studio.example.net",
        port: 443
    )
    let record = try ClientConfiguredRouteRecordV1(
        configuredRouteID: WireBytes16(Data(0x40...0x4f)),
        endpoint: endpoint,
        provenance: .privateDNS
    )
    let configuration = NetworkClientRouteAttemptConfigurationV0(
        clientID: UUID(),
        expectedHostID: UUID(),
        expectedDeviceID: UUID(),
        signer: NetworkClientTestSigner(),
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 1,
                monotonicNowMilliseconds: 1
            )
        },
        nonce: { try WireBytes32(Data(repeating: 1, count: 32)) },
        messageID: { WireUUID(UUID()) },
        pinnedLeafEvaluator: { _ in
            throw CocoaError(.fileReadCorruptFile)
        },
        verificationQueue: DispatchQueue(label: "route-binding.verify"),
        connectionQueue: DispatchQueue(label: "route-binding.connection"),
        receivedCommand: { _ in },
        configuredRoutes: try ClientConfiguredRouteCatalogV1(
            records: [record]
        )
    )
    #expect(try configuration.configuredRoute(forExactEndpoint: endpoint)
        == record)
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.winnerNotConfigured) {
        _ = try configuration.configuredRoute(
            forExactEndpoint: EndpointCandidate(
                kind: .dns,
                value: "other.example.net",
                port: 443
            )
        )
    }
}

@Test func authenticatedRouteClassUsesOnlyExactConfiguredProvenance() throws {
    func record(
        _ kind: EndpointKind,
        _ value: String,
        _ provenance: ClientConfiguredRouteProvenanceV1,
        byte: UInt8
    ) throws -> ClientConfiguredRouteRecordV1 {
        try ClientConfiguredRouteRecordV1(
            configuredRouteID: WireBytes16(Data(repeating: byte, count: 16)),
            endpoint: EndpointCandidate(
                kind: kind,
                value: value,
                port: 443
            ),
            provenance: provenance
        )
    }

    #expect(NetworkClientAuthenticatedRouteClassV1.project(try record(
        .bonjour,
        "mac-test._maccompanion._tcp.local.",
        .localDiscovery,
        byte: 1
    )) == .lan)
    #expect(NetworkClientAuthenticatedRouteClassV1.project(try record(
        .ipv4,
        "192.168.40.10",
        .directPrivateAddress,
        byte: 2
    )) == nil)
    #expect(NetworkClientAuthenticatedRouteClassV1.project(try record(
        .dns,
        "studio.example.net",
        .privateDNS,
        byte: 3
    )) == .privateDNS)
    #expect(NetworkClientAuthenticatedRouteClassV1.project(try record(
        .ipv6,
        "fd00::2",
        .privateNetwork,
        byte: 4
    )) == .privateNetwork)
    #expect(NetworkClientAuthenticatedRouteClassV1.project(nil) == nil)
}

private struct NetworkClientOperationApprovalSignerV0:
    ClientOperationApprovalSigningV1
{
    func signOperationApprovalInput(_ input: Data) async throws -> Data {
        Data(repeating: 0x77, count: 64)
    }
}

private struct NetworkClientInteractiveApprovalSignerV0:
    ClientInteractiveApprovalSigningV0
{
    func signAfterUserPresence(_ input: Data) async throws -> Data {
        Data(repeating: 0x78, count: 64)
    }
}

private final class NetworkClientActEventRecorderV0: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "MacCompanionTests.NetworkActEvents"
    )
    private var countStorage = 0
    var count: Int { queue.sync { countStorage } }
    func record(_ event: ClientActChannelEventV1) {
        queue.sync { countStorage += 1 }
    }
}

private final class NetworkClientObserveEventRecorderV0: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "MacCompanionTests.NetworkObserveEvents"
    )
    private var valuesStorage: [ClientObserveChannelEventV0] = []
    var values: [ClientObserveChannelEventV0] {
        queue.sync { valuesStorage }
    }
    func record(_ event: ClientObserveChannelEventV0) {
        queue.sync { valuesStorage.append(event) }
    }
}

private final class NetworkClientPrimaryProductRecorderV0:
    @unchecked Sendable
{
    private let queue = DispatchQueue(
        label: "MacCompanionTests.NetworkPrimaryProductEvents"
    )
    private var selectionsStorage: [NetworkClientPrimaryProductSelectionV0] = []
    private var terminationsStorage: [(UUID, Data)] = []

    var selections: [NetworkClientPrimaryProductSelectionV0] {
        queue.sync { selectionsStorage }
    }

    var terminations: [(UUID, Data)] {
        queue.sync { terminationsStorage }
    }

    func selected(_ value: NetworkClientPrimaryProductSelectionV0) {
        queue.sync { selectionsStorage.append(value) }
    }

    func terminated(hostID: UUID, connectionID: Data) {
        queue.sync { terminationsStorage.append((hostID, connectionID)) }
    }
}

private final class NetworkClientObservePublicationRecorderV0:
    @unchecked Sendable
{
    private let queue = DispatchQueue(
        label: "MacCompanionTests.NetworkObservePublications"
    )
    private var valuesStorage: [NetworkClientObservePublicationV0] = []

    var values: [NetworkClientObservePublicationV0] {
        queue.sync { valuesStorage }
    }

    func record(_ value: NetworkClientObservePublicationV0) {
        queue.sync { valuesStorage.append(value) }
    }
}

private func networkClientPairedHost(
    clientID: UUID,
    hostID: UUID,
    deviceID: UUID,
    fingerprint: Data
) throws -> ClientDurablePairedHostV0 {
    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let pairingID = UUID()
    return try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: pairingID,
            clientID: clientID,
            hostID: hostID,
            deviceID: deviceID,
            hostFingerprint: fingerprint,
            endpoints: [try EndpointCandidate(
                kind: .dns,
                value: "router.example.test",
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
}

private func networkClientActDescriptor() throws
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
        capabilityID: "maccompanion.test.networkAction",
        schemaVersion: 1,
        providerID: "maccompanion.test.network",
        providerVersion: "1.0.0",
        providerGeneration: UUID(),
        executionRevision: UUID(),
        englishTitle: "Network action",
        englishSummary: "A bounded test action.",
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
            cancellation: .notApplicable
        )
    ))
}

private func networkClientAcceptedControlSession(
    primary session: ClientAuthenticatedSessionV0
) throws -> ClientInteractiveAcceptedSessionV0 {
    let epoch = session.authorizationEpoch
    return ClientInteractiveAcceptedSessionV0(
        primary: try ClientInteractivePrimaryBindingV0(
            hostID: session.hostID,
            hostFingerprint: Data(repeating: 0x22, count: 32),
            clientID: session.clientID,
            primaryConnectionID: session.connectionID,
            authorizationEpoch: epoch,
            grantRevision: session.grantRevision,
            policyRevision: session.policyRevision
        ),
        interactiveSessionID: UUID(),
        authorizationEpoch: epoch,
        expiresAtUnixMilliseconds: 62_000,
        inputChannel: try InteractiveChannelOffer(
            channelID: WireUUID(UUID()),
            role: .input,
            credential: WireBytes32(Data(repeating: 0x31, count: 32)),
            issuedAtUnixMilliseconds: 2_000,
            expiresAtUnixMilliseconds: 32_000
        ),
        mediaChannel: try InteractiveChannelOffer(
            channelID: WireUUID(UUID()),
            role: .media,
            credential: WireBytes32(Data(repeating: 0x32, count: 32)),
            issuedAtUnixMilliseconds: 2_000,
            expiresAtUnixMilliseconds: 32_000
        )
    )
}

@Test func primaryProductCandidatePublishesOnlyAfterExactSelection()
    async throws
{
    let base = try makeNetworkClientPumpHarness()
    let productEvents = NetworkClientPrimaryProductRecorderV0()
    let selectedTerminations = NetworkClientPrimaryProductRecorderV0()
    let observePublications = NetworkClientObservePublicationRecorderV0()
    let applicationState = NetworkClientPrimaryApplicationStateV0(
        hostID: base.hostID,
        selectedPrimaryTerminated: {
            selectedTerminations.terminated(
                hostID: base.hostID,
                connectionID: Data()
            )
        }
    )
    let pairedHost = try networkClientPairedHost(
        clientID: await base.session.clientID,
        hostID: base.hostID,
        deviceID: base.deviceID,
        fingerprint: base.fingerprint
    )
    let selectedEndpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.1.20",
        port: 47_474
    )
    let candidate = NetworkClientPrimaryProductCandidateV0(
        endpoint: selectedEndpoint,
        authenticatedRouteClass: .lan,
        configuration: NetworkClientPrimaryProductConfigurationV0(
            pairedHost: pairedHost,
            approvalSigner: NetworkClientOperationApprovalSignerV0(),
            interactiveApprovalSigner:
                NetworkClientInteractiveApprovalSignerV0(),
            clock: {
                NetworkClientClockSnapshotV0(
                    wallNowUnixMilliseconds: 2_004,
                    monotonicNowMilliseconds: 1_003
                )
            },
            messageID: { WireUUID(UUID()) },
            events: applicationState.productEvents.combined(with:
                NetworkClientPrimaryProductEventsV0(
                publishObserve: { observePublications.record($0) },
                primarySelected: { productEvents.selected($0) },
                primaryTerminated: { hostID, connectionID in
                    productEvents.terminated(
                        hostID: hostID,
                        connectionID: connectionID
                    )
                }
            ))
        )
    )
    let pump = NetworkClientPrimaryFramePumpV0(
        io: base.io,
        tlsHandoff: await base.pump.tlsHandoff,
        session: base.session,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 2_004,
                monotonicNowMilliseconds: 1_003
            )
        },
        authenticated: { try await candidate.authenticated($0) },
        readyForAuthenticatedTraffic: { base.ready.record() },
        receivedCommand: { try await candidate.receive($0) },
        terminal: { reason in
            Task { await base.terminals.record(reason) }
        }
    )
    try await candidate.bind(pump)
    let harness = NetworkClientPumpHarnessV0(
        io: base.io,
        pump: pump,
        session: base.session,
        start: base.start,
        helloMessageID: base.helloMessageID,
        hostID: base.hostID,
        deviceID: base.deviceID,
        fingerprint: base.fingerprint,
        authenticated: base.authenticated,
        ready: base.ready,
        commands: base.commands,
        terminals: base.terminals
    )
    try await authenticateNetworkClientPump(harness)
    for _ in 0..<1_000 where base.ready.count == 0 {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }

    #expect(productEvents.selections.isEmpty)
    #expect(observePublications.values.isEmpty)
    #expect(applicationState.snapshot().availability == .disconnected)
    #expect(applicationState.snapshot().revision == 0)
    await #expect(
        throws: NetworkClientPrimaryApplicationCommandErrorV0.unavailable
    ) {
        try await applicationState.refreshStatus()
    }
    await candidate.selectedAsPrimary()
    let selection = try #require(productEvents.selections.first)
    let session = selection.authenticatedSession
    #expect(session.hostID == base.hostID)
    #expect(selection.endpoint == selectedEndpoint)
    #expect(selection.authenticatedRouteClass == .lan)
    #expect(session.connectionID == Data(repeating: 0x11, count: 16))
    #expect(applicationState.snapshot().availability == .connected)
    #expect(applicationState.snapshot().connectionID == session.connectionID)
    #expect(applicationState.snapshot().authenticatedRouteClass == .lan)
    #expect(applicationState.snapshot().revision == 1)
    #expect(applicationState.snapshot().controlChannel != nil)
    #expect(applicationState.snapshot().controlState == .inactive)

    let controlSubmitted = try await applicationState
        .beginInteractiveControl(effects: [.view])
    #expect(controlSubmitted == .requestSubmitted(effects: [.view]))
    let controlSent = await waitForNetworkClientSentCount(base.io, 3)
    let controlRequest = try decodeNetworkClientSentFrame(
        controlSent[2],
        as: InteractiveSessionRequestBody.self
    )
    #expect(controlRequest.body.effects == [.view])
    #expect(applicationState.snapshot().controlState
        == .requestSubmitted(effects: [.view]))
    #expect(applicationState.snapshot().revision == 2)

    try await applicationState.reloadApprovedActions()
    let catalogSent = await waitForNetworkClientSentCount(base.io, 4)
    let catalogRequest = try decodeNetworkClientSentFrame(
        catalogSent[3],
        as: CapabilityRegistryRequestBody.self
    )
    let catalogResponse = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: catalogRequest.messageID,
        sentAtUnixMilliseconds: 2_005,
        body: try CapabilityRegistryResponseBody(
            registryGeneration: WireUUID(UUID()),
            grantRevision: 3,
            policyRevision: 4,
            capabilities: [try networkClientActDescriptor()],
            nextAfterCapabilityID: nil
        )
    )
    #expect(await waitForNetworkClientPendingReceive(base.io))
    base.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(catalogResponse))
    )
    for _ in 0..<1_000 where applicationState.snapshot().catalog == nil {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(applicationState.snapshot().catalog?.capabilities.count == 1)
    #expect(applicationState.snapshot().revision == 3)

    try await applicationState.refreshStatus()
    let sent = await waitForNetworkClientSentCount(base.io, 5)
    let request = try decodeNetworkClientSentFrame(
        sent[4],
        as: StatusSnapshotRequestBody.self
    )
    let response = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: request.messageID,
        sentAtUnixMilliseconds: 2_005,
        body: try StatusSnapshotBody(
            hostID: WireUUID(base.hostID),
            generation: WireUUID(UUID()),
            revision: 1,
            observedAtUnixMilliseconds: 2_004,
            validForMilliseconds: 1_000,
            hostState: .userSessionActive,
            system: SystemOverview(
                osName: "macOS",
                osVersion: "26.0",
                osBuild: "25A100",
                uptimeSeconds: 500,
                cpuUtilizationBasisPoints: 1_250,
                memoryTotalBytes: 16_000,
                memoryUsedBytes: 8_000,
                storageTotalBytes: 100_000,
                storageAvailableBytes: 40_000,
                powerSource: .ac,
                batteryLevelPercent: nil
            )
        )
    )
    #expect(await waitForNetworkClientPendingReceive(base.io))
    base.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(response))
    )
    for _ in 0..<1_000 where observePublications.values.isEmpty {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    let publication = try #require(observePublications.values.first)
    #expect(publication.hostID == base.hostID)
    #expect(publication.connectionID == session.connectionID)
    #expect(applicationState.snapshot().observedStatus != nil)
    #expect(applicationState.snapshot().revision == 4)

    applicationState.productEvents.publishObserve(
        NetworkClientObservePublicationV0(
            hostID: base.hostID,
            connectionID: Data(repeating: 0x99, count: 16),
            event: publication.event
        )
    )
    #expect(applicationState.snapshot().revision == 4)
    #expect(applicationState.droppedStaleEventCount() == 1)

    await candidate.primaryTerminated()
    await candidate.primaryTerminated()
    #expect(productEvents.terminations.count == 1)
    #expect(productEvents.terminations.first?.0 == base.hostID)
    #expect(productEvents.terminations.first?.1 == session.connectionID)
    #expect(await selection.observeChannel.state == .invalidated)
    #expect(await selection.controlChannel.phase() == .closed)
    #expect(applicationState.snapshot().availability == .disconnected)
    #expect(applicationState.snapshot().observedStatus != nil)
    #expect(applicationState.snapshot().catalog == nil)
    #expect(applicationState.snapshot().actChannel == nil)
    #expect(applicationState.snapshot().controlChannel == nil)
    #expect(applicationState.snapshot().controlState == .inactive)
    #expect(applicationState.snapshot().revision == 5)
    #expect(selectedTerminations.terminations.count == 1)
    await #expect(
        throws: NetworkClientPrimaryApplicationCommandErrorV0.unavailable
    ) {
        try await applicationState.reloadApprovedActions()
    }

    let replacementConnectionID = Data(repeating: 0x44, count: 16)
    let replacementSession = ClientAuthenticatedSessionV0(
        clientID: session.clientID,
        hostID: session.hostID,
        deviceID: session.deviceID,
        connectionID: replacementConnectionID,
        deviceState: session.deviceState,
        authorizationEpoch: session.authorizationEpoch,
        grantRevision: session.grantRevision,
        policyRevision: session.policyRevision,
        hostState: session.hostState,
        features: session.features,
        serverTimeUnixMilliseconds: session.serverTimeUnixMilliseconds
    )
    applicationState.productEvents.primarySelected(
        NetworkClientPrimaryProductSelectionV0(
            endpoint: selection.endpoint,
            authenticatedRouteClass: .privateDNS,
            authenticatedSession: replacementSession,
            observeChannel: selection.observeChannel,
            actChannel: selection.actChannel,
            controlChannel: selection.controlChannel
        )
    )
    #expect(applicationState.snapshot().availability == .connected)
    #expect(applicationState.snapshot().connectionID == replacementConnectionID)
    #expect(applicationState.snapshot().authenticatedRouteClass == .privateDNS)
    #expect(applicationState.snapshot().observedStatus == nil)
    #expect(applicationState.snapshot().revision == 6)

    let acceptedControl = try networkClientAcceptedControlSession(
        primary: replacementSession
    )
    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .accepted(
                session: acceptedControl,
                effects: [.view, .pointer]
            )
        )
    )
    #expect(applicationState.snapshot().controlState == .accepted(
        interactiveSessionID: acceptedControl.interactiveSessionID,
        expiresAtUnixMilliseconds:
            acceptedControl.expiresAtUnixMilliseconds,
        effects: [.view, .pointer]
    ))
    #expect(applicationState.snapshot().revision == 7)

    // A transport cannot skip from approval directly to active.
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .active
    )
    #expect(applicationState.snapshot().revision == 7)
    #expect(applicationState.droppedStaleEventCount() == 2)

    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .roleChannelsConnecting
    )
    #expect(applicationState.snapshot().controlState == .preparing(
        interactiveSessionID: acceptedControl.interactiveSessionID,
        expiresAtUnixMilliseconds:
            acceptedControl.expiresAtUnixMilliseconds,
        effects: [.view, .pointer],
        phase: .roleChannelsConnecting
    ))
    #expect(applicationState.snapshot().revision == 8)
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .failed(.roleChannelsConnecting)
    )
    #expect(applicationState.snapshot().controlState == .preparationFailed(
        interactiveSessionID: acceptedControl.interactiveSessionID,
        effects: [.view, .pointer],
        phase: .roleChannelsConnecting
    ))
    #expect(applicationState.snapshot().revision == 9)

    // A new exact acceptance may retry; each later phase remains monotonic.
    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .accepted(
                session: acceptedControl,
                effects: [.view, .pointer]
            )
        )
    )
    #expect(applicationState.snapshot().revision == 10)
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .roleChannelsConnecting
    )
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .roleChannelsReady
    )
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .initialSurfacePreparing
    )
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .active
    )
    #expect(applicationState.snapshot().controlState == .active(
        interactiveSessionID: acceptedControl.interactiveSessionID,
        expiresAtUnixMilliseconds:
            acceptedControl.expiresAtUnixMilliseconds,
        effects: [.view, .pointer]
    ))
    #expect(applicationState.snapshot().revision == 14)
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: acceptedControl.interactiveSessionID,
        progress: .active
    )
    #expect(applicationState.snapshot().revision == 14)
    applicationState.acceptInteractiveProductProgress(
        connectionID: replacementConnectionID,
        interactiveSessionID: UUID(),
        progress: .active
    )
    #expect(applicationState.snapshot().revision == 14)
    #expect(applicationState.droppedStaleEventCount() == 3)

    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .ended(
                interactiveSessionID:
                    acceptedControl.interactiveSessionID,
                endedAtUnixMilliseconds: 2_100
            )
        )
    )
    #expect(applicationState.snapshot().revision == 14)
    #expect(applicationState.droppedStaleEventCount() == 4)
    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .endSubmitted(
                interactiveSessionID:
                    acceptedControl.interactiveSessionID,
                effects: [.view, .pointer]
            )
        )
    )
    #expect(applicationState.snapshot().controlState == .ending(
        interactiveSessionID: acceptedControl.interactiveSessionID,
        effects: [.view, .pointer]
    ))
    #expect(applicationState.snapshot().revision == 15)
    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .ended(
                interactiveSessionID:
                    acceptedControl.interactiveSessionID,
                endedAtUnixMilliseconds: 2_100
            )
        )
    )
    #expect(applicationState.snapshot().controlState == .inactive)
    #expect(applicationState.snapshot().revision == 16)

    let controlError = ClientInteractiveRemoteErrorV0(
        code: "policy.denied",
        retry: .afterUserAction
    )
    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .remoteRejected(controlError)
        )
    )
    #expect(applicationState.snapshot().controlState
        == .remoteRejected(controlError))
    #expect(applicationState.snapshot().revision == 17)
    applicationState.productEvents.publishControl(
        NetworkClientControlPublicationV0(
            hostID: base.hostID,
            connectionID: session.connectionID,
            event: .requestSubmitted(effects: [.view])
        )
    )
    #expect(applicationState.snapshot().revision == 17)

    let catalogError = ClientOperationRemoteErrorV1(
        try ProtocolErrorResponseBody(
            code: "capability.registryChanged",
            retry: .afterReconnect
        )
    )
    applicationState.productEvents.publishAct(
        NetworkClientActPublicationV0(
            hostID: base.hostID,
            connectionID: replacementConnectionID,
            event: .remoteError(request: .catalog, error: catalogError)
        )
    )
    #expect(applicationState.snapshot().catalog == nil)
    #expect(applicationState.snapshot().operationState == nil)
    #expect(applicationState.snapshot().catalogRemoteError == catalogError)
    #expect(applicationState.snapshot().revision == 18)

    applicationState.productEvents.primaryTerminated(
        base.hostID,
        session.connectionID
    )
    applicationState.productEvents.publishObserve(publication)
    #expect(applicationState.snapshot().connectionID == replacementConnectionID)
    #expect(applicationState.snapshot().observedStatus == nil)
    #expect(applicationState.snapshot().revision == 18)
    #expect(applicationState.droppedStaleEventCount() == 7)
    #expect(selectedTerminations.terminations.count == 1)

    applicationState.productEvents.primaryTerminated(
        base.hostID,
        replacementConnectionID
    )
    #expect(applicationState.snapshot().availability == .disconnected)
    #expect(applicationState.snapshot().authenticatedRouteClass == nil)
    #expect(applicationState.snapshot().revision == 19)
    #expect(selectedTerminations.terminations.count == 2)
    var updateIterator = applicationState.updates.makeAsyncIterator()
    #expect(await updateIterator.next()?.revision == 19)

    let losingEvents = NetworkClientPrimaryProductRecorderV0()
    let losingCandidate = NetworkClientPrimaryProductCandidateV0(
        endpoint: selectedEndpoint,
        authenticatedRouteClass: nil,
        configuration: NetworkClientPrimaryProductConfigurationV0(
            pairedHost: pairedHost,
            approvalSigner: NetworkClientOperationApprovalSignerV0(),
            interactiveApprovalSigner:
                NetworkClientInteractiveApprovalSignerV0(),
            clock: {
                NetworkClientClockSnapshotV0(
                    wallNowUnixMilliseconds: 2_004,
                    monotonicNowMilliseconds: 1_003
                )
            },
            messageID: { WireUUID(UUID()) },
            events: NetworkClientPrimaryProductEventsV0(
                primarySelected: { losingEvents.selected($0) },
                primaryTerminated: { hostID, connectionID in
                    losingEvents.terminated(
                        hostID: hostID,
                        connectionID: connectionID
                    )
                }
            )
        )
    )
    try await losingCandidate.bind(pump)
    try await losingCandidate.authenticated(session)
    await losingCandidate.primaryTerminated()
    await losingCandidate.selectedAsPrimary()
    #expect(losingEvents.selections.isEmpty)
    #expect(losingEvents.terminations.isEmpty)

    // Media failure after initial activation must not leave the workspace
    // active. Wrong-primary/session callbacks remain unable to retire it.
    applicationState.productEvents.primarySelected(selection)
    let liveControl = try networkClientAcceptedControlSession(primary: session)
    applicationState.productEvents.publishControl(.init(hostID: base.hostID,
        connectionID: session.connectionID,
        event: .accepted(session: liveControl, effects: [.view, .pointer])))
    for progress: NetworkClientInteractiveProductProgressV0 in [
        .roleChannelsConnecting, .roleChannelsReady, .initialSurfacePreparing, .active
    ] {
        applicationState.acceptInteractiveProductProgress(connectionID: session.connectionID,
            interactiveSessionID: liveControl.interactiveSessionID, progress: progress)
    }
    let liveRevision = applicationState.snapshot().revision
    for (connection, interactive) in [(replacementConnectionID, liveControl.interactiveSessionID),
                                       (session.connectionID, UUID())] {
        applicationState.acceptInteractiveProductProgress(connectionID: connection,
            interactiveSessionID: interactive, progress: .failed(.initialSurface))
        #expect(applicationState.snapshot().revision == liveRevision)
    }
    applicationState.acceptInteractiveProductProgress(connectionID: session.connectionID,
        interactiveSessionID: liveControl.interactiveSessionID, progress: .failed(.initialSurface))
    #expect(applicationState.snapshot().controlState == .preparationFailed(
        interactiveSessionID: liveControl.interactiveSessionID, effects: [.view, .pointer], phase: .initialSurface))
    #expect(applicationState.snapshot().revision == liveRevision + 1)
    #expect(applicationState.snapshot().availability == .connected)
    applicationState.acceptInteractiveProductProgress(connectionID: session.connectionID,
        interactiveSessionID: liveControl.interactiveSessionID, progress: .failed(.initialSurface))
    #expect(applicationState.snapshot().revision == liveRevision + 1)

    await pump.cancel()
}

@Test func selectedLANPrimaryRefreshesStatusBeforeHostLivenessExpires()
    async throws
{
    let base = try makeNetworkClientPumpHarness()
    let pairedHost = try networkClientPairedHost(
        clientID: await base.session.clientID,
        hostID: base.hostID,
        deviceID: base.deviceID,
        fingerprint: base.fingerprint
    )
    let sleep = NetworkClientImmediateThenBlockingSleepV0()
    let candidate = NetworkClientPrimaryProductCandidateV0(
        endpoint: try EndpointCandidate(
            kind: .ipv4,
            value: "192.168.1.20",
            port: 47_474
        ),
        authenticatedRouteClass: .lan,
        configuration: NetworkClientPrimaryProductConfigurationV0(
            pairedHost: pairedHost,
            approvalSigner: NetworkClientOperationApprovalSignerV0(),
            interactiveApprovalSigner:
                NetworkClientInteractiveApprovalSignerV0(),
            clock: {
                NetworkClientClockSnapshotV0(
                    wallNowUnixMilliseconds: 2_004,
                    monotonicNowMilliseconds: 1_003
                )
            },
            messageID: { WireUUID(UUID()) },
            events: .discarding,
            livenessRefreshSleep: { try await sleep.sleep() }
        )
    )
    let pump = NetworkClientPrimaryFramePumpV0(
        io: base.io,
        tlsHandoff: await base.pump.tlsHandoff,
        session: base.session,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 2_004,
                monotonicNowMilliseconds: 1_003
            )
        },
        authenticated: { try await candidate.authenticated($0) },
        readyForAuthenticatedTraffic: { base.ready.record() },
        receivedCommand: { try await candidate.receive($0) },
        terminal: { reason in
            Task { await base.terminals.record(reason) }
        }
    )
    try await candidate.bind(pump)
    let harness = NetworkClientPumpHarnessV0(
        io: base.io,
        pump: pump,
        session: base.session,
        start: base.start,
        helloMessageID: base.helloMessageID,
        hostID: base.hostID,
        deviceID: base.deviceID,
        fingerprint: base.fingerprint,
        authenticated: base.authenticated,
        ready: base.ready,
        commands: base.commands,
        terminals: base.terminals
    )
    try await authenticateNetworkClientPump(harness)
    for _ in 0..<1_000 where base.ready.count == 0 {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    let authenticatedSends = await waitForNetworkClientSentCount(base.io, 2)
    #expect(authenticatedSends.count == 2)
    #expect(base.ready.count == 1)
    #expect(sleep.callCount == 0)

    await candidate.selectedAsPrimary()
    let sent = await waitForNetworkClientSentCount(base.io, 3)
    #expect(sleep.callCount >= 1)
    #expect(sent.count == 3)
    let request = try decodeNetworkClientSentFrame(
        try #require(sent.count > 2 ? sent[2] : nil),
        as: StatusSnapshotRequestBody.self
    )
    let response = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: request.messageID,
        sentAtUnixMilliseconds: 2_005,
        body: try StatusSnapshotBody(
            hostID: WireUUID(base.hostID),
            generation: WireUUID(UUID()),
            revision: 1,
            observedAtUnixMilliseconds: 2_004,
            validForMilliseconds: 1_000,
            hostState: .userSessionActive,
            system: SystemOverview(
                osName: "macOS",
                osVersion: "26.0",
                osBuild: "25A100",
                uptimeSeconds: 500,
                cpuUtilizationBasisPoints: 1_250,
                memoryTotalBytes: 16_000,
                memoryUsedBytes: 8_000,
                storageTotalBytes: 100_000,
                storageAvailableBytes: 40_000,
                powerSource: .ac,
                batteryLevelPercent: nil
            )
        )
    )
    #expect(await waitForNetworkClientPendingReceive(base.io))
    base.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(response))
    )
    try? await Task.sleep(nanoseconds: 10_000_000)
    #expect(await base.terminals.values.isEmpty)

    await candidate.primaryTerminated()
    await pump.cancel()
}

@Test func clientPumpRoutesAuthenticatedObserveAndActThroughBridge()
    async throws
{
    let base = try makeNetworkClientPumpHarness()
    let actEvents = NetworkClientActEventRecorderV0()
    let observeEvents = NetworkClientObserveEventRecorderV0()
    let bridge = NetworkClientPrimaryRouterBridgeV0(
        pairedHost: try networkClientPairedHost(
            clientID: await base.session.clientID,
            hostID: base.hostID,
            deviceID: base.deviceID,
            fingerprint: base.fingerprint
        ),
        approvalSigner: NetworkClientOperationApprovalSignerV0(),
        monotonicNowNanoseconds: { 1_003_000_000 },
        observeEnvironment: ClientObserveChannelEnvironmentV0(
            makeMessageID: { WireUUID(UUID()) },
            wallNowUnixMilliseconds: { 2_004 },
            monotonicNowMilliseconds: { 1_003 }
        ),
        actEnvironment: ClientActChannelEnvironmentV1(
            makeMessageID: { WireUUID(UUID()) },
            wallNowUnixMilliseconds: { 2_004 }
        ),
        publishObserve: { observeEvents.record($0) },
        publishAct: { actEvents.record($0) }
    )
    let pump = NetworkClientPrimaryFramePumpV0(
        io: base.io,
        tlsHandoff: await base.pump.tlsHandoff,
        session: base.session,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 2_004,
                monotonicNowMilliseconds: 1_003
            )
        },
        authenticated: { try await bridge.authenticated($0) },
        readyForAuthenticatedTraffic: { base.ready.record() },
        receivedCommand: { try await bridge.receive($0) },
        terminal: { reason in
            Task {
                await bridge.primaryTerminated()
                await base.terminals.record(reason)
            }
        }
    )
    try await bridge.bind(pump: pump)
    let harness = NetworkClientPumpHarnessV0(
        io: base.io,
        pump: pump,
        session: base.session,
        start: base.start,
        helloMessageID: base.helloMessageID,
        hostID: base.hostID,
        deviceID: base.deviceID,
        fingerprint: base.fingerprint,
        authenticated: base.authenticated,
        ready: base.ready,
        commands: base.commands,
        terminals: base.terminals
    )
    try await authenticateNetworkClientPump(harness)
    for _ in 0..<1_000 where await bridge.currentActChannel() == nil {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    let channel = try #require(await bridge.currentActChannel())
    let observe = try #require(await bridge.currentObserveChannel())
    #expect(base.ready.count == 1)
    try await channel.reloadCatalog()
    let sent = await waitForNetworkClientSentCount(base.io, 3)
    let request = try decodeNetworkClientSentFrame(
        sent[2],
        as: CapabilityRegistryRequestBody.self
    )
    let response = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: request.messageID,
        sentAtUnixMilliseconds: 2_005,
        body: try CapabilityRegistryResponseBody(
            registryGeneration: WireUUID(UUID()),
            grantRevision: 3,
            policyRevision: 4,
            capabilities: [try networkClientActDescriptor()],
            nextAfterCapabilityID: nil
        )
    )
    #expect(await waitForNetworkClientPendingReceive(base.io))
    base.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(response))
    )
    for _ in 0..<1_000 where actEvents.count == 0 {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(actEvents.count == 1)
    #expect(await channel.state == .ready)

    try await observe.requestStatus()
    let observeSent = await waitForNetworkClientSentCount(base.io, 4)
    let statusRequest = try decodeNetworkClientSentFrame(
        observeSent[3],
        as: StatusSnapshotRequestBody.self
    )
    let statusResponse = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: statusRequest.messageID,
        sentAtUnixMilliseconds: 2_005,
        body: try StatusSnapshotBody(
            hostID: WireUUID(base.hostID),
            generation: WireUUID(UUID()),
            revision: 1,
            observedAtUnixMilliseconds: 2_004,
            validForMilliseconds: 1_000,
            hostState: .userSessionActive,
            system: SystemOverview(
                osName: "macOS",
                osVersion: "26.0",
                osBuild: "25A100",
                uptimeSeconds: 500,
                cpuUtilizationBasisPoints: 1_250,
                memoryTotalBytes: 16_000,
                memoryUsedBytes: 8_000,
                storageTotalBytes: 100_000,
                storageAvailableBytes: 40_000,
                powerSource: .ac,
                batteryLevelPercent: nil
            )
        )
    )
    #expect(await waitForNetworkClientPendingReceive(base.io))
    base.io.deliver(
        try LengthPrefixedFrameDecoder.encode(WireCodec.encode(statusResponse))
    )
    for _ in 0..<1_000 where observeEvents.values.isEmpty {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(observeEvents.values.count == 1)
    #expect(await observe.retainedStatus?.snapshot.revision == 1)

    await pump.cancel()
    _ = await waitForNetworkClientPumpTerminal(base.terminals)
    for _ in 0..<1_000 where await channel.state != .invalidated {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(await channel.state == .invalidated)
    #expect(await observe.state == .invalidated)
}
