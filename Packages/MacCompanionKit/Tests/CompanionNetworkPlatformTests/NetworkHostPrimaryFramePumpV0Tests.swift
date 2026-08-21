import CompanionAuthentication
import CompanionDomain
import CompanionHost
import CompanionHostSession
@testable import CompanionNetworkPlatform
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Dispatch
import Foundation
import Network
import Testing

private enum NetworkHostPumpTestError: Error {
    case unused
    case sendFailed
}

private struct NetworkHostUnusedStatusProvider:
    HostStatusSnapshotProvidingV0
{
    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        throw NetworkHostPumpTestError.unused
    }
}

private struct NetworkHostUnusedOperationDispatcher:
    AuthenticatedOperationWireDispatchingV0
{
    func dispatch(
        requestJSON: Data,
        context: AuthenticatedOperationCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        throw NetworkHostPumpTestError.unused
    }
}

private struct NetworkHostUnusedCapabilityDispatcher:
    AuthenticatedCapabilityRegistryDispatchingV1
{
    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        throw NetworkHostPumpTestError.unused
    }
}

private actor NetworkHostUnusedInteractiveDispatcher:
    AuthenticatedInteractiveWireDispatchingV0
{
    private(set) var closeCount = 0

    func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        throw NetworkHostPumpTestError.unused
    }

    func primarySessionClosed() async {
        closeCount += 1
    }
}

private final class NetworkHostFakeFrameIOV0:
    NetworkHostPrimaryFrameIOV0,
    @unchecked Sendable
{
    typealias ReceiveCompletion = @Sendable (Data?, Bool, Bool) -> Void

    private let queue = DispatchQueue(
        label: "MacCompanionTests.HostFakeFrameIO"
    )
    private var stateHandler: (@Sendable (
        NetworkHostPrimaryFrameIOStateV0
    ) -> Void)?
    private var receiveCompletion: ReceiveCompletion?
    private var sentStorage: [Data] = []
    private var startCountStorage = 0
    private var cancelCountStorage = 0
    private var sendFailureStorage = false

    var sent: [Data] { queue.sync { sentStorage } }
    var startCount: Int { queue.sync { startCountStorage } }
    var cancelCount: Int { queue.sync { cancelCountStorage } }
    var hasPendingReceive: Bool { queue.sync { receiveCompletion != nil } }

    func failSends() {
        queue.sync { sendFailureStorage = true }
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostPrimaryFrameIOStateV0
        ) -> Void
    ) {
        queue.sync { stateHandler = handler }
    }

    func start(queue: DispatchQueue) {
        self.queue.sync { startCountStorage += 1 }
    }

    func receive(
        maximumLength: Int,
        completion: @escaping ReceiveCompletion
    ) {
        precondition(
            maximumLength
                == NetworkHostPrimaryFramePumpV0.maximumReceiveChunkBytes
        )
        queue.sync { receiveCompletion = completion }
    }

    func send(_ data: Data) async throws {
        let shouldFail = queue.sync { sendFailureStorage }
        if shouldFail { throw NetworkHostPumpTestError.sendFailed }
        queue.sync { sentStorage.append(data) }
    }

    func cancel() {
        queue.sync { cancelCountStorage += 1 }
    }

    func updateState(_ state: NetworkHostPrimaryFrameIOStateV0) {
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

private actor NetworkHostPumpTerminalRecorderV0 {
    private(set) var values: [NetworkHostPrimaryTerminationReasonV0] = []

    func record(_ value: NetworkHostPrimaryTerminationReasonV0) {
        values.append(value)
    }
}

private struct NetworkHostPumpHarnessV0 {
    let directory: URL
    let io: NetworkHostFakeFrameIOV0
    let pump: NetworkHostPrimaryFramePumpV0
    let session: AuthenticatedPrimarySessionV0
    let terminals: NetworkHostPumpTerminalRecorderV0
    let interactive: NetworkHostUnusedInteractiveDispatcher
    let binding: HostApplicationTLSBinding

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func makeNetworkHostPumpHarness() async throws
    -> NetworkHostPumpHarnessV0
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-host-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    let store = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let hostKey = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: hostKey.publicKey.x963Representation
    )
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
    let interactive = NetworkHostUnusedInteractiveDispatcher()
    let session = try AuthenticatedPrimarySessionV0(
        hostID: UUID(),
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 0,
        authentication: ApplicationAuthenticationAuthority(
            deviceReader: store
        ),
        status: NetworkHostUnusedStatusProvider(),
        operations: NetworkHostUnusedOperationDispatcher(),
        capabilities: NetworkHostUnusedCapabilityDispatcher(),
        interactive: interactive
    )
    let io = NetworkHostFakeFrameIOV0()
    let terminals = NetworkHostPumpTerminalRecorderV0()
    let pump = NetworkHostPrimaryFramePumpV0(
        io: io,
        tlsBinding: binding,
        session: session,
        context: {
            NetworkHostRequestContextV0(
                hostState: .userSessionActive,
                wallNowUnixMilliseconds: 2_001,
                monotonicNowMilliseconds: 101,
                responseMessageID: WireUUID(
                    UUID(
                        uuidString:
                            "018f9000-0000-7000-8000-000000000002"
                    )!
                )
            )
        },
        terminal: { reason in
            Task { await terminals.record(reason) }
        }
    )
    return NetworkHostPumpHarnessV0(
        directory: directory,
        io: io,
        pump: pump,
        session: session,
        terminals: terminals,
        interactive: interactive,
        binding: binding
    )
}

@Test func hostPumpVerifiedTransferDoesNotRestartConnection() async throws {
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }

    try await harness.pump.beginOnVerifiedReadyConnection()

    #expect(harness.io.startCount == 0)
    #expect(await waitForNetworkHostReceive(harness.io))
    await #expect(
        throws: NetworkHostPrimaryFramePumpErrorV0.invalidConfiguration
    ) {
        try await harness.pump.beginOnVerifiedReadyConnection()
    }
    await harness.pump.cancel()
    #expect(harness.io.cancelCount == 1)
}

@Test func hostPumpVerifiedConnectionCanOnlyBeConsumedOnce() async throws {
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }
    let verified = NetworkHostVerifiedReadyConnectionV0(
        connection: NWConnection(
            host: "127.0.0.1",
            port: 9,
            using: .tcp
        ),
        tlsBinding: harness.binding
    )
    let context: @Sendable () -> NetworkHostRequestContextV0 = {
        NetworkHostRequestContextV0(
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 2_001,
            monotonicNowMilliseconds: 101,
            responseMessageID: WireUUID(UUID())
        )
    }

    _ = try NetworkHostPrimaryFramePumpV0(
        verifiedReadyConnection: verified,
        session: harness.session,
        context: context
    )
    #expect(
        throws:
            NetworkHostAcceptedConnectionErrorV0
                .verifiedConnectionAlreadyConsumed
    ) {
        _ = try NetworkHostPrimaryFramePumpV0(
            verifiedReadyConnection: verified,
            session: harness.session,
            context: context
        )
    }
}

private func networkHostUnknownHelloFrame() throws -> Data {
    let hello = try WireEnvelope(
        messageID: WireUUID(
            UUID(
                uuidString: "018f9000-0000-7000-8000-000000000001"
            )!
        ),
        correlationID: nil,
        sentAtUnixMilliseconds: 2_000,
        body: try AuthHelloBody(
            clientID: WireUUID(UUID()),
            clientNonce: WireBytes32(Data(repeating: 0x33, count: 32))
        )
    )
    return try LengthPrefixedFrameDecoder.encode(
        try WireCodec.encode(hello)
    )
}

private func waitForNetworkHostReceive(
    _ io: NetworkHostFakeFrameIOV0
) async -> Bool {
    for _ in 0..<1_000 {
        if io.hasPendingReceive { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return io.hasPendingReceive
}

private func waitForNetworkHostTerminal(
    _ recorder: NetworkHostPumpTerminalRecorderV0
) async -> [NetworkHostPrimaryTerminationReasonV0] {
    for _ in 0..<1_000 {
        let values = await recorder.values
        if !values.isEmpty { return values }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await recorder.values
}

private func waitForNetworkHostSend(
    _ io: NetworkHostFakeFrameIOV0
) async -> [Data] {
    for _ in 0..<1_000 {
        let sent = io.sent
        if !sent.isEmpty { return sent }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return io.sent
}

@Test func hostPumpInjectedIOStartsOnceAndWaitsForReady() async throws {
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }

    try await harness.pump.start(
        queue: DispatchQueue(label: "MacCompanionTests.HostPumpStart")
    )
    #expect(harness.io.startCount == 1)
    await #expect(
        throws: NetworkHostPrimaryFramePumpErrorV0.invalidConfiguration
    ) {
        try await harness.pump.start(
            queue: DispatchQueue(
                label: "MacCompanionTests.HostPumpDuplicateStart"
            )
        )
    }

    harness.io.updateState(.setup)
    harness.io.updateState(.preparing)
    harness.io.updateState(.waiting)
    await Task.yield()
    #expect(!harness.io.hasPendingReceive)
    #expect(await harness.terminals.values.isEmpty)

    harness.io.updateState(.ready)
    #expect(await waitForNetworkHostReceive(harness.io))
    await harness.pump.cancel()
    #expect(harness.io.cancelCount == 1)
}

@Test func hostPumpInjectedIOFramesOpaqueChallengeResponse() async throws {
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }
    try await harness.pump.start(
        queue: DispatchQueue(label: "MacCompanionTests.HostPumpChallenge")
    )
    harness.io.updateState(.ready)
    #expect(await waitForNetworkHostReceive(harness.io))

    harness.io.deliver(try networkHostUnknownHelloFrame())
    let sent = await waitForNetworkHostSend(harness.io)
    #expect(sent.count == 1)
    var decoder = LengthPrefixedFrameDecoder()
    let frames = try decoder.append(sent[0])
    #expect(frames.count == 1)
    let challenge = try WireCodec.decode(
        WireEnvelope<AuthChallengeBody>.self,
        from: frames[0]
    )
    #expect(
        challenge.correlationID
            == WireUUID(
                UUID(
                    uuidString: "018f9000-0000-7000-8000-000000000001"
                )!
            )
    )
    #expect(await harness.session.phase == .awaitingProof)
    await harness.pump.cancel()
}

@Test func hostPumpInjectedIOClosesOnResponseSendFailure() async throws {
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }
    harness.io.failSends()
    try await harness.pump.start(
        queue: DispatchQueue(label: "MacCompanionTests.HostPumpSendFailure")
    )
    harness.io.updateState(.ready)
    #expect(await waitForNetworkHostReceive(harness.io))

    harness.io.deliver(try networkHostUnknownHelloFrame())

    #expect(
        await waitForNetworkHostTerminal(harness.terminals)
            == [.protocolOrSessionFailure]
    )
    #expect(harness.io.sent.isEmpty)
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func hostPumpInjectedIORejectsMalformedFrame() async throws {
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }
    try await harness.pump.start(
        queue: DispatchQueue(label: "MacCompanionTests.HostPumpMalformed")
    )
    harness.io.updateState(.ready)
    #expect(await waitForNetworkHostReceive(harness.io))

    harness.io.deliver(Data([0, 0, 0, 0]))

    #expect(
        await waitForNetworkHostTerminal(harness.terminals)
            == [.protocolOrSessionFailure]
    )
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.session.phase == .closed)
}

@Test func hostPumpInjectedIOTeardownIsExactlyOnceAfterReceiveFailure()
    async throws
{
    let harness = try await makeNetworkHostPumpHarness()
    defer { harness.remove() }
    try await harness.pump.start(
        queue: DispatchQueue(label: "MacCompanionTests.HostPumpReceiveFailure")
    )
    harness.io.updateState(.ready)
    #expect(await waitForNetworkHostReceive(harness.io))

    harness.io.deliver(nil, failed: true)
    #expect(
        await waitForNetworkHostTerminal(harness.terminals)
            == [.receiveFailed]
    )
    harness.io.updateState(.failed)
    harness.io.updateState(.cancelled)
    await harness.pump.cancel()
    await Task.yield()

    #expect(await harness.terminals.values == [.receiveFailed])
    #expect(harness.io.cancelCount == 1)
    #expect(await harness.interactive.closeCount == 1)
    #expect(await harness.session.phase == .closed)
}
