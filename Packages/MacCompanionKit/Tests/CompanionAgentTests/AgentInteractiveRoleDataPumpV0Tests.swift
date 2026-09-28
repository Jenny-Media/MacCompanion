import CompanionAgentNetworkPlatform
import CompanionAgent
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveClient
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CoreGraphics
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
    private(set) var retiredPairs = 0
    private let retirementGate: AsyncStream<Void>?
    func retireInteractiveMedia(pair: AgentInteractiveReadyRolePairV0) async {
        retiredPairs += 1
        if let retirementGate { for await _ in retirementGate { break } }
    }
    private(set) var inputs: [InteractiveInputEnvelope] = []
    private var media: [AgentInteractiveOutboundMediaRecordV0]

    init(media: [AgentInteractiveOutboundMediaRecordV0], retirementGate: AsyncStream<Void>? = nil) {
        self.retirementGate = retirementGate
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
    #expect(await route.retiredPairs == 1)
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
    #expect(await route.retiredPairs == 1)
    #expect(await route.inputs.isEmpty)
    #expect(mediaIO.sent.isEmpty)
    #expect(await terminal.reasons == [.inputFenceMismatch])
}

private struct HermeticInputPipelineObservationV0: Equatable, Sendable {
    let admittedInputCount: Int
    let admittedSequence: UInt64
    let constructedEventCount: Int
    let unicodeEventCount: Int
    let exactConstructedSequenceMatched: Bool
}

private final class HermeticInputPipelineSinkV0:
    CoreGraphicsConstructedEventSinkV0, @unchecked Sendable
{
    private let lock = NSLock()
    private var unicodeValues: [String] = []
    private var eventCount = 0

    func receiveConstructedEvent(_ event: CGEvent) throws {
        var units = [UniChar](repeating: 0, count: 64)
        var actualLength = 0
        units.withUnsafeMutableBufferPointer { buffer in
            event.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &actualLength,
                unicodeString: buffer.baseAddress!
            )
        }
        let value = String(utf16CodeUnits: units, count: actualLength)
        lock.withLock {
            eventCount += 1
            if !value.isEmpty { unicodeValues.append(value) }
        }
    }

    func observation(
        admittedInputCount: Int,
        admittedSequence: UInt64,
        expectedTextEvents: [String]
    ) -> HermeticInputPipelineObservationV0 {
        let expectedConstructedValues = expectedTextEvents.flatMap {
            [$0, $0]
        }
        return lock.withLock {
            HermeticInputPipelineObservationV0(
                admittedInputCount: admittedInputCount,
                admittedSequence: admittedSequence,
                constructedEventCount: eventCount,
                unicodeEventCount: unicodeValues.count,
                exactConstructedSequenceMatched:
                    unicodeValues == expectedConstructedValues
            )
        }
    }
}

private actor HermeticInputPipelineRouteV0:
    AgentInteractiveMenuRoleDataRoutingV0
{
    func retireInteractiveMedia(pair: AgentInteractiveReadyRolePairV0) {}
    private var admission = InteractiveInputAdmissionAuthority()
    private var planner = MacInteractiveInputPlannerV0()
    private let session: InteractiveSessionStateMachine
    private let surfaces: AdaptiveSurfaceAuthority
    private let fence: InteractiveCommandFence
    private let geometry: MacDisplayGeometrySnapshotV0
    private let sink = HermeticInputPipelineSinkV0()
    private let expectedTextEvents: [String]
    private var admittedInputCount = 0

    init(
        session: InteractiveSessionStateMachine,
        surface: AdaptiveSurfaceDescriptor,
        displayID: UUID,
        expectedTextEvents: [String]
    ) throws {
        self.session = session
        surfaces = try AdaptiveSurfaceAuthority(
            desktop: surface,
            monotonicNowMilliseconds: 2_000
        )
        fence = InteractiveCommandFence(
            leaseID: UUID(),
            hostID: UUID(),
            deviceID: UUID(),
            interactiveSessionID: surface.interactiveSessionID,
            authorizationEpoch: surface.authorizationEpoch,
            selectedDisplayID: displayID,
            surfaceID: surface.surfaceID,
            surfaceRevision: .init(rawValue: surface.surfaceRevision.rawValue),
            coordinateRevision: .init(
                rawValue: surface.coordinateSpaceRevision.rawValue
            )
        )
        geometry = try MacDisplayGeometrySnapshotV0(
            selectedDisplayID: displayID,
            coordinateRevision: fence.coordinateRevision,
            logicalBounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            backingScaleFactor: 2,
            rotation: .degrees0
        )
        self.expectedTextEvents = expectedTextEvents
    }

    func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        pair: AgentInteractiveReadyRolePairV0,
        nowMonotonicNanoseconds: UInt64
    ) throws {
        try admission.admit(
            envelope,
            session: session,
            surfaces: surfaces,
            hostMonotonicMilliseconds: nowMonotonicNanoseconds / 1_000_000
        )
        let descriptions = try planner.plan(envelope.input)
        _ = try CoreGraphicsNoPostInputConstructorV0().construct(
            descriptions,
            fence: fence,
            geometry: geometry,
            currentCursorPosition: CGPoint(x: 100, y: 100),
            sink: sink
        )
        admittedInputCount += 1
    }

    func nextInteractiveMediaRecord(
        pair: AgentInteractiveReadyRolePairV0
    ) async throws -> AgentInteractiveOutboundMediaRecordV0? {
        while admittedInputCount < expectedTextEvents.count {
            try Task.checkCancellation()
            await Task.yield()
        }
        return nil
    }

    func observation() -> HermeticInputPipelineObservationV0 {
        sink.observation(
            admittedInputCount: admittedInputCount,
            admittedSequence: admission.stream.lastSequence,
            expectedTextEvents: expectedTextEvents
        )
    }
}

private func hermeticInputPipelineSessionV0(
    sessionID: UUID,
    epoch: AuthorizationEpoch
) throws -> InteractiveSessionStateMachine {
    var session = InteractiveSessionStateMachine()
    _ = try session.apply(.request(
        sessionID: sessionID,
        authorizationEpoch: epoch,
        approvalDeadlineMonotonicMilliseconds: 60_000
    ))
    _ = try session.apply(
        .approvalConsumed(monotonicNowMilliseconds: 1_000)
    )
    _ = try session.apply(
        .executorReadyUnlocked(monotonicNowMilliseconds: 2_000)
    )
    return session
}

private func hermeticInputPipelineSurfaceV0(
    sessionID: UUID,
    epoch: AuthorizationEpoch,
    surfaceID: UUID
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: epoch,
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_920,
        encodedHeight: 1_080,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard, .text],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func hermeticInputPipelineFrameV0(
    _ envelope: InteractiveInputEnvelope
) throws -> Data {
    let body = try InteractiveInputCodec.encode(envelope)
    let length = UInt32(body.count)
    return Data([
        UInt8(length >> 24),
        UInt8((length >> 16) & 0xff),
        UInt8((length >> 8) & 0xff),
        UInt8(length & 0xff),
    ]) + body
}

@Test func clientTextInputTraversesFramingAdmissionPlanningAndConstruction()
    async throws
{
    let sessionID = UUID()
    let surfaceID = UUID()
    let displayID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 4)
    let expectedTextEvents = ["h", "e", "l", "l", "o", " "]
    let surface = try hermeticInputPipelineSurfaceV0(
        sessionID: sessionID,
        epoch: epoch,
        surfaceID: surfaceID
    )
    var producer = try ClientInputProducerV0(
        interactiveSessionID: sessionID,
        authorizationEpoch: epoch
    )
    try producer.activate(acknowledged: surface)
    var framedInput = Data()
    for (offset, value) in expectedTextEvents.enumerated() {
        let envelope = try producer.makeInput(
            messageID: WireUUID(UUID()),
            clientMonotonicMilliseconds: UInt64(1_000 + offset),
            payload: .text(value)
        )
        framedInput += try hermeticInputPipelineFrameV0(envelope)
    }

    let inputIO = AgentRoleDataConnectionIOV0(receiveBuffer: framedInput)
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
    let route = try HermeticInputPipelineRouteV0(
        session: hermeticInputPipelineSessionV0(
            sessionID: sessionID,
            epoch: epoch
        ),
        surface: surface,
        displayID: displayID,
        expectedTextEvents: expectedTextEvents
    )
    let terminal = AgentRoleDataTerminalRecorderV0()
    let pump = AgentInteractiveRoleDataPumpV0(
        pair: pair,
        route: route,
        monotonicNowNanoseconds: { 2_000_000_000 },
        terminal: { _, reason in await terminal.record(reason) }
    )

    do {
        try await pump.run()
        Issue.record("role pump unexpectedly returned")
    } catch let reason as AgentInteractiveRoleDataPumpErrorV0 {
        #expect(reason == .mediaSourceClosed)
    }

    let observation = await route.observation()
    #expect(producer.lastSequence == 6)
    #expect(observation.admittedInputCount == 6)
    #expect(observation.admittedSequence == 6)
    #expect(observation.constructedEventCount == 12)
    #expect(observation.unicodeEventCount == 12)
    #expect(observation.exactConstructedSequenceMatched)
    #expect(await terminal.reasons == [.mediaSourceClosed])
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

@Test func concurrentPumpCancellationJoinsMediaRetirement() async throws {
    let session = UUID(), epoch = AuthorizationEpoch(rawValue: 1)
    let pair = try AgentInteractiveReadyRolePairV0(
        input: agentRoleDataChannelV0(role: .input, sessionID: session, epoch: epoch, io: AgentRoleDataConnectionIOV0()),
        media: agentRoleDataChannelV0(role: .media, sessionID: session, epoch: epoch, io: AgentRoleDataConnectionIOV0()))
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    let route = AgentRoleDataMenuRouteV0(media: [], retirementGate: stream)
    let completion = AgentRoleDataTerminalRecorderV0()
    let pump = AgentInteractiveRoleDataPumpV0(pair: pair, route: route, terminal: { _, _ in })
    let first = Task { await pump.cancel() }
    for _ in 0..<100 {
        if await route.retiredPairs == 1 { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await route.retiredPairs == 1)
    let second = Task { await pump.cancel(); await completion.record(.cancelled) }
    try await Task.sleep(for: .milliseconds(20))
    #expect(await completion.reasons.isEmpty)
    continuation.yield(())
    await first.value
    await second.value
    #expect(await route.retiredPairs == 1)
    #expect(await completion.reasons == [.cancelled])
}
