import CompanionAgentNetworkPlatform
import CompanionAgent
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private enum AgentRoleDataPumpTestErrorV0: Error {
    case cancelled
}

private final class AgentRoleDataConnectionIOV0: @unchecked Sendable {
    private let lock = NSLock()
    private var receiveBuffer: Data
    private var receiveContinuation: CheckedContinuation<
        NetworkHostInteractiveRoleTrafficChunkV0,
        Error
    >?
    private var sentStorage: [Data] = []
    private var cancelCountStorage = 0
    private var cancelledStorage = false

    init(receiveBuffer: Data = Data()) {
        self.receiveBuffer = receiveBuffer
    }

    var sent: [Data] { lock.withLock { sentStorage } }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }

    func receive(maximumLength: Int) async throws
        -> NetworkHostInteractiveRoleTrafficChunkV0
    {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result = lock.withLock { () -> Result<Data, Error>? in
                    guard !cancelledStorage else {
                        return .failure(
                            AgentRoleDataPumpTestErrorV0.cancelled
                        )
                    }
                    guard !receiveBuffer.isEmpty else {
                        receiveContinuation = continuation
                        return nil
                    }
                    let count = min(maximumLength, receiveBuffer.count)
                    let value = Data(receiveBuffer.prefix(count))
                    receiveBuffer.removeFirst(count)
                    return .success(value)
                }
                if let result {
                    continuation.resume(with: result.map {
                        NetworkHostInteractiveRoleTrafficChunkV0(data: $0)
                    })
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func send(_ data: Data) {
        lock.withLock { sentStorage.append(data) }
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<
            NetworkHostInteractiveRoleTrafficChunkV0,
            Error
        >? in
            guard !cancelledStorage else { return nil }
            cancelCountStorage += 1
            cancelledStorage = true
            let value = receiveContinuation
            receiveContinuation = nil
            return value
        }
        continuation?.resume(throwing: AgentRoleDataPumpTestErrorV0.cancelled)
    }
}

private actor AgentRoleDataMenuRouteV0:
    AgentInteractiveMenuRoleDataRoutingV0
{
    private(set) var inputs: [InteractiveInputEnvelope] = []
    private var media: [AgentInteractiveOutboundMediaRecordV0]

    init(media: [AgentInteractiveOutboundMediaRecordV0]) {
        self.media = media
    }

    func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        pair: AgentInteractiveReadyRolePairV0,
        nowMonotonicNanoseconds: UInt64
    ) {
        inputs.append(envelope)
    }

    func nextInteractiveMediaRecord(
        pair: AgentInteractiveReadyRolePairV0
    ) async throws -> AgentInteractiveOutboundMediaRecordV0? {
        while inputs.isEmpty {
            try Task.checkCancellation()
            await Task.yield()
        }
        guard !media.isEmpty else { return nil }
        return media.removeFirst()
    }
}

private actor AgentRoleDataTerminalRecorderV0 {
    private(set) var reasons: [AgentInteractiveRoleDataPumpErrorV0] = []

    func record(_ reason: AgentInteractiveRoleDataPumpErrorV0) {
        reasons.append(reason)
    }
}

private struct AgentRoleDataRuntimeTerminationV0: Equatable, Sendable {
    let interactiveSessionID: UUID
    let primaryConnectionID: Data
    let reason: InteractiveSessionEndReason
}

private actor AgentRoleDataRuntimeFenceV0:
    AgentInteractiveRuntimeFenceOwningV0
{
    var stateStorage: AgentInteractiveRuntimeBindingAuthorityStateV1
    private(set) var terminations: [AgentRoleDataRuntimeTerminationV0] = []

    init(_ state: AgentInteractiveRuntimeBindingAuthorityStateV1) {
        stateStorage = state
    }

    func state() -> AgentInteractiveRuntimeBindingAuthorityStateV1 {
        stateStorage
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) {
        terminations.append(AgentRoleDataRuntimeTerminationV0(
            interactiveSessionID: interactiveSessionID,
            primaryConnectionID: primaryConnectionID,
            reason: reason
        ))
    }
}

private func agentRoleDataChannelV0(
    role: InteractiveChannelRoleName,
    sessionID: UUID,
    epoch: AuthorizationEpoch,
    io: AgentRoleDataConnectionIOV0
) -> NetworkHostInteractiveReadyRoleConnectionV0 {
    let channel = HostInteractiveReadyRoleChannelV0(hello:
        try! InteractiveChannelHelloBody(
            channelID: WireUUID(UUID()),
            role: role,
            clientID: WireUUID(UUID(uuidString:
                "11111111-1111-4111-8111-111111111111"
            )!),
            primaryConnectionID: try! WireBytes16(
                Data(repeating: 1, count: 16)
            ),
            interactiveSessionID: WireUUID(sessionID),
            authorizationEpoch: epoch,
            clientNonce: try! WireBytes32(Data(repeating: 2, count: 32))
        )
    )
    return NetworkHostInteractiveReadyRoleConnectionV0(
        tlsBinding: try! agentRoleDataTLSBindingV0(),
        channel: channel,
        receive: { maximumLength in
            try await io.receive(maximumLength: maximumLength)
        },
        send: { data in io.send(data) },
        cancel: { io.cancel() }
    )
}

private func agentRoleDataTLSBindingV0() throws
    -> HostApplicationTLSBinding
{
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    return try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: CompanionSecurityV0.hostFingerprint(
            subjectPublicKeyInfoDER: spki
        )
    )
}

private func agentRoleDataInputFrameV0(
    sessionID: UUID,
    epoch: AuthorizationEpoch
) throws -> (InteractiveInputEnvelope, Data) {
    let envelope = try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(sessionID),
        authorizationEpoch: epoch,
        sequence: 1,
        clientMonotonicMilliseconds: 1,
        surfaceID: WireUUID(UUID()),
        surfaceRevision: SurfaceRevision(rawValue: 1),
        coordinateSpaceRevision: CoordinateSpaceRevision(rawValue: 1),
        input: .reset
    )
    let body = try InteractiveInputCodec.encode(envelope)
    let length = UInt32(body.count)
    return (envelope, Data([
        UInt8(length >> 24),
        UInt8((length >> 16) & 0xff),
        UInt8((length >> 8) & 0xff),
        UInt8(length & 0xff),
    ]) + body)
}

@Test func agentRoleDataPumpForwardsInputAndSendsOneMediaAtATime()
    async throws
{
    let sessionID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 5)
    let (inputEnvelope, inputFrame) = try agentRoleDataInputFrameV0(
        sessionID: sessionID,
        epoch: epoch
    )
    let inputIO = AgentRoleDataConnectionIOV0(receiveBuffer: inputFrame)
    let mediaIO = AgentRoleDataConnectionIOV0()
    let pair = try AgentInteractiveReadyRolePairV0(
        input: agentRoleDataChannelV0(
            role: .input,
            sessionID: sessionID,
            epoch: epoch,
            io: inputIO
        ),
        media: agentRoleDataChannelV0(
            role: .media,
            sessionID: sessionID,
            epoch: epoch,
            io: mediaIO
        )
    )
    let header = try MediaRecordHeader(
        type: .discontinuity,
        payloadLength: 0,
        interactiveSessionID: sessionID,
        authorizationEpoch: epoch,
        surfaceID: UUID(),
        surfaceRevision: SurfaceRevision(rawValue: 1),
        coordinateSpaceRevision: CoordinateSpaceRevision(rawValue: 1),
        mediaSequence: 1,
        presentationTimeNanoseconds: 0,
        encodedWidth: 0,
        encodedHeight: 0
    )
    let route = AgentRoleDataMenuRouteV0(media: [
        try AgentInteractiveOutboundMediaRecordV0(
            header: header,
            payload: Data()
        ),
    ])
    let terminal = AgentRoleDataTerminalRecorderV0()
    let pump = AgentInteractiveRoleDataPumpV0(
        pair: pair,
        route: route,
        monotonicNowNanoseconds: { 10 },
        terminal: { _, reason in await terminal.record(reason) }
    )

    do {
        try await pump.run()
        Issue.record("role pump unexpectedly returned")
    } catch let reason as AgentInteractiveRoleDataPumpErrorV0 {
        #expect(reason == .mediaSourceClosed)
    }
    #expect(await route.inputs == [inputEnvelope])
    #expect(mediaIO.sent == [header.encode()])
    #expect(inputIO.cancelCount == 1)
    #expect(mediaIO.cancelCount == 1)
    #expect(await terminal.reasons == [.mediaSourceClosed])
}

@Test func agentRoleDataPumpRejectsInputOutsideAuthenticatedFence()
    async throws
{
    let sessionID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 5)
    let (_, inputFrame) = try agentRoleDataInputFrameV0(
        sessionID: UUID(),
        epoch: epoch
    )
    let inputIO = AgentRoleDataConnectionIOV0(receiveBuffer: inputFrame)
    let mediaIO = AgentRoleDataConnectionIOV0()
    let pair = try AgentInteractiveReadyRolePairV0(
        input: agentRoleDataChannelV0(
            role: .input,
            sessionID: sessionID,
            epoch: epoch,
            io: inputIO
        ),
        media: agentRoleDataChannelV0(
            role: .media,
            sessionID: sessionID,
            epoch: epoch,
            io: mediaIO
        )
    )
    let route = AgentRoleDataMenuRouteV0(media: [])
    let terminal = AgentRoleDataTerminalRecorderV0()
    let pump = AgentInteractiveRoleDataPumpV0(
        pair: pair,
        route: route,
        terminal: { _, reason in await terminal.record(reason) }
    )

    do {
        try await pump.run()
        Issue.record("role pump unexpectedly returned")
    } catch let reason as AgentInteractiveRoleDataPumpErrorV0 {
        #expect(reason == .inputFenceMismatch)
    }
    #expect(await route.inputs.isEmpty)
    #expect(mediaIO.sent.isEmpty)
    #expect(await terminal.reasons == [.inputFenceMismatch])
}

@Test func agentRoleDataBindingAuthorityRequiresRuntimeGenerationAndOwnsTeardown()
    async throws
{
    let sessionID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 5)
    let inputIO = AgentRoleDataConnectionIOV0()
    let mediaIO = AgentRoleDataConnectionIOV0()
    let pair = try AgentInteractiveReadyRolePairV0(
        input: agentRoleDataChannelV0(
            role: .input,
            sessionID: sessionID,
            epoch: epoch,
            io: inputIO
        ),
        media: agentRoleDataChannelV0(
            role: .media,
            sessionID: sessionID,
            epoch: epoch,
            io: mediaIO
        )
    )
    let runtime = AgentRoleDataRuntimeFenceV0(.active(
        generation: 7,
        interactiveSessionID: sessionID
    ))
    let authority = AgentInteractiveRoleDataBindingAuthorityV0(
        runtime: runtime
    )
    let route = AgentRoleDataMenuRouteV0(media: [])
    try await authority.bind(route: route, generation: 7)
    try await authority.accept(pair)
    #expect(await authority.state() == .active(
        generation: 7,
        interactiveSessionID: sessionID
    ))

    #expect(await authority.invalidate(generation: 7))
    #expect(await authority.state() == .unavailable)
    #expect(inputIO.cancelCount == 1)
    #expect(mediaIO.cancelCount == 1)
    #expect(await runtime.terminations == [
        AgentRoleDataRuntimeTerminationV0(
            interactiveSessionID: sessionID,
            primaryConnectionID: pair.primaryConnectionID,
            reason: .menuAppUnavailable
        ),
    ])
}

@Test func agentRoleDataBindingAuthorityRejectsMismatchedRuntimeFence()
    async throws
{
    let sessionID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 5)
    let pair = try AgentInteractiveReadyRolePairV0(
        input: agentRoleDataChannelV0(
            role: .input,
            sessionID: sessionID,
            epoch: epoch,
            io: AgentRoleDataConnectionIOV0()
        ),
        media: agentRoleDataChannelV0(
            role: .media,
            sessionID: sessionID,
            epoch: epoch,
            io: AgentRoleDataConnectionIOV0()
        )
    )
    let runtime = AgentRoleDataRuntimeFenceV0(.active(
        generation: 8,
        interactiveSessionID: sessionID
    ))
    let authority = AgentInteractiveRoleDataBindingAuthorityV0(
        runtime: runtime
    )
    try await authority.bind(
        route: AgentRoleDataMenuRouteV0(media: []),
        generation: 7
    )

    await #expect(throws:
        AgentInteractiveRoleDataBindingAuthorityErrorV0
            .runtimeFenceMismatch
    ) {
        try await authority.accept(pair)
    }
    #expect(await authority.state() == .bound(generation: 7))
}
